package Workflow::Server::UR;

use strict;
use base 'Workflow::Server';
use POE;
use POE::Component::IKC::Client;
use POE::Component::IKC::Responder;
use Log::Log4perl qw(:easy);

use Workflow::Server::Hub;
use Workflow ();

BEGIN {
    if (defined $ENV{WF_TRACE_UR}) {
        Log::Log4perl->easy_init($DEBUG);
    } else {
        Log::Log4perl->easy_init($ERROR);
    }
};

sub setup {
    my ($class, $hub_hostname, $hub_port) = @_;

    $Storable::forgive_me = 1;

    create_ikc_responder();
    DEBUG "ur process connecting to hub $hub_hostname:$hub_port";

    POE::Component::IKC::Client->spawn(
        ip         => $hub_hostname,
        port       => $hub_port,
        name       => 'UR',
        on_connect => sub { _build($hub_hostname, $hub_port); },
    );
    $0 = "workflow urd connected to hubd at $hub_hostname:$hub_port";
}


sub _build {
    my ($hub_hostname, $hub_port) = @_;

    DEBUG "UR server _build hub_port=$hub_port";
    POE::Session->create(
        heap => {
            hub_hostname => $hub_hostname,
            hub_port => $hub_port,
            changes => 0,  ## this means possible changes, not that anything actually changed and needs to be synced.  For my purposes I don't care.
            unchanged_commits => 0,
        },
        inline_states => {
            _start      => \&_workflow_start,
            _stop       => \&_workflow_stop,
            announce    => \&_workflow_announce,

            sig_HUP      => \&_workflow_sig_HUP,
            register     => \&_workflow_register,
            unregister   => \&_workflow_unregister,
            output_relay => \&_workflow_output_relay,
            error_relay  => \&_workflow_error_relay,

            load_and_execute  => \&_workflow_load_and_execute,
            resume            => \&_workflow_resume,
            begin_instance    => \&_workflow_begin_instance,
            end_instance      => \&_workflow_end_instance,
            finalize_instance => \&_workflow_finalize_instance,
            schedule_instance => \&_workflow_schedule_instance,
            quit              => \&_workflow_quit,
            quit_stage_2      => \&_workflow_quit_stage_2,

            commit => \&_workflow_commit,
        },
    );
}

sub dispatch {
    my ($class, $instance, $input) = @_;

    $instance->status('scheduled');

    my $try_shortcut_first =
            $instance->operation->operation_type->can('shortcut') ? 1 : 0;

    POE::Kernel->post('IKC','post','poe://Hub/dispatch/add_work', {
        instance => $instance,
        operation_type => $instance->operation->operation_type,
        input => $input,
        shortcut_flag => $try_shortcut_first,
        out_log => $instance->current->stdout,
        err_log => $instance->current->stderr
    });
}

sub _util_error_walker {
    my $i = shift;
    my @errors = ();

    foreach my $p ($i,$i->peers) {
        my @new = $p->current->errors;
        push @errors, @new;

        if ($p->can('child_instances')) {
            foreach my $ci ($p->child_instances) {
                push @errors, _util_error_walker($ci);
            }
        }
    }

    return @errors;
}


sub _workflow_start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    DEBUG "workflow _start";
    $kernel->alias_set("workflow");
    $kernel->post('IKC','publish','workflow',
        [qw(load_and_execute
            resume
            begin_instance
            end_instance
            finalize_instance
            schedule_instance
            quit)]
    );

    $kernel->sig('HUP','sig_HUP');

    $heap->{record} = Workflow::Service->create(
        hostname => $heap->{hub_hostname},
        port => $heap->{hub_port}
    );
    UR::Context->commit();

    $kernel->yield('announce');
    $kernel->delay('commit', 30);
}

sub _workflow_stop {
    my $heap = $_[HEAP];

    DEBUG "workflow _stop";
    $heap->{record}->delete();
    UR::Context->commit();
}

sub _workflow_announce {
    my $kernel = $_[KERNEL];

    $kernel->post('IKC', 'post', 'poe://Hub/passthru/register_ur');
}

sub _workflow_sig_HUP {
    my ($heap) = @_[HEAP];

    $heap->{record}->delete();
    UR::Context->commit();

    # NOTE: not calling sig_handled so this is still terminal
}

sub _workflow_quit {
    my ($kernel, $session, $kill_hub_flag) = @_[KERNEL, SESSION, ARG0];

    DEBUG "workflow quit";
    if(defined $kill_hub_flag && $kill_hub_flag) {
        # call quit of the hub and setup our quit_stage_2 as a callback.
        $kernel->post('IKC', 'call', 'poe://Hub/dispatch/quit',
                undef, 'poe:quit_stage_2');
    } else {
        $kernel->yield('quit_stage_2');
    }
}

sub _workflow_quit_stage_2 {
    my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];

    DEBUG "workflow quit_stage_2";
    $kernel->post($session, 'shutdown');

    $kernel->call($session, 'commit');
    $kernel->alarm_remove_all();
    $kernel->alias_remove('workflow');

    $kernel->post('IKC', 'shutdown');
}

sub _workflow_commit {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    if($heap->{changes} > 0) {
        UR::Context->commit();
        $heap->{changes} = 0;
    }
    $kernel->delay('commit', 30);
}

sub _workflow_register {
    my ($name, $real) = @_[ARG1, ARG2];
    DEBUG "workflow register ", ($real ? '' : 'alias '), "$name";
}

sub _workflow_unregister {
    my ($kernel, $name, $real) = @_[KERNEL, ARG1, ARG2];
    DEBUG "workflow unregister ", ($real ? '' : 'alias '), "$name";
}

sub _load {
    my ($heap, $xml) = @_;

    DEBUG "Loading Workflow::Operation from xml";
    my $workflow = Workflow::Operation->create_from_xml($xml);

    my $id = $workflow->id;
    DEBUG "Loaded Workflow::Operation($id) from xml";
    return $workflow;
}

sub _workflow_load_and_execute {
    my ($kernel, $session, $heap, $arg) = @_[KERNEL, SESSION, HEAP, ARG0];
    my ($xml, $input, $return_address) = @$arg;

    DEBUG "workflow load_and_execute (return_address:$return_address)";
    $heap->{changes}++;

    my $workflow = _load($heap, $xml);
    my $executor = Workflow::Executor::Server->get();
    $workflow->set_all_executor($executor);

    my %opts = (
        input => $input
    );
    $opts{output_cb} = $session->postback('output_relay', $return_address);
    $opts{error_cb} = $session->postback('error_relay', $return_address);

    my $instance = $workflow->execute(%opts);

    if($instance->can('parent_execution_id') and
            exists($ENV{'WORKFLOW_PARENT_EXECUTION'})) {
        $instance->parent_execution_id($ENV{'WORKFLOW_PARENT_EXECUTION'});
    }

    $workflow->wait();
}

sub _workflow_resume {
    my ($kernel, $heap, $session, $arg) = @_[KERNEL, HEAP, SESSION, ARG0];
    my ($id, $return_address) = @$arg;

    DEBUG "workflow resume $id";
    $heap->{changes}++;

    my @tree = Workflow::Operation::Instance->get(
        id => $id,
        -recurse => ['parent_instance_id', 'instance_id'],
    );
    my $instance = Workflow::Operation::Instance->get($id);

    my $executor = Workflow::Executor::Server->get();
    $instance->operation->set_all_executor($executor);

    my $output_cb = $session->postback('output_relay', $return_address);
    $instance->output_cb($output_cb);

    my $error_cb = $session->postback('error_relay', $return_address);
    $instance->error_cb($error_cb);

    if ($instance->is_done) {
        Workflow::Operation::InstanceExecution::Error->create(
            execution => $instance->current,
            error => "Cannot resume finished workflow"
        );
        $kernel->yield('error_relay', [$return_address], [$instance]);
        return;
    }

    $instance->resume();
    $instance->operation->wait();
}

sub _workflow_output_relay {
    my ($kernel, $session, $heap, $xarg, $yarg) =
            @_[KERNEL, SESSION, HEAP, ARG0, ARG1];
    my ($output_dest) = @$xarg;
    my ($instance) = @$yarg;

    DEBUG "workflow output_relay";
    $instance->output_cb(undef);
    $instance->error_cb(undef);

    $kernel->refcount_decrement($session->ID, 'anon_event');
    $kernel->refcount_decrement($session->ID, 'anon_event');

    # undef hole is where $instance->current was.  removing that from the return set.
    $kernel->post('IKC', 'post', 'poe://Hub/passthru/relay_result', 
            [$output_dest, $instance->id, $instance->output, undef]);
}

sub _workflow_error_relay {
    my ($kernel, $session, $heap, $xarg, $yarg) =
            @_[KERNEL, SESSION, HEAP, ARG0, ARG1];
    my ($error_dest) = @$xarg;
    my ($instance) = @$yarg;

    DEBUG "workflow error_relay";
    $instance->output_cb(undef);
    $instance->error_cb(undef);

    $kernel->refcount_decrement($session->ID, 'anon_event');
    $kernel->refcount_decrement($session->ID, 'anon_event');

    my @errors = _util_error_walker($instance);
    $kernel->post('IKC', 'post', 'poe://Hub/passthru/relay_result',
            [$error_dest, $instance->id, $instance->output, undef, \@errors]);
}

sub _workflow_begin_instance {
    my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
    my ($id, $dispatch_id) = @$arg;

    DEBUG "workflow begin_instance";
    $heap->{changes}++;

    my $instance = Workflow::Operation::Instance->get($id);

    $instance->status('running');
    $instance->current->start_time(Workflow::Time->now());
    $instance->current->dispatch_identifier($dispatch_id);
}

sub _workflow_end_instance {
    my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
    my ($id, $status, $output, $error_string, $metrics) = @$arg;

    DEBUG "workflow end_instance";
    $heap->{changes}++;

    my $instance = Workflow::Operation::Instance->get($id);
    $instance->status($status);
    $instance->current->end_time(Workflow::Time->now());

    while(my ($k,$v) = each(%$metrics)) {
        $instance->current->add_metric(name => $k, value => $v);
    }
    if($status eq 'done') {
        $instance->output({ %{ $instance->output }, %$output });
    } elsif($status eq 'crashed') {
        Workflow::Operation::InstanceExecution::Error->create(
            execution => $instance->current,
            error => $error_string
        );
    }
}

sub _workflow_finalize_instance {
    my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
    my ($id, $cpu_sec, $mem, $swap) = @$arg;

    DEBUG "workflow finalize_instance $id $cpu_sec $mem $swap";
    $heap->{changes}++;

    my $instance = Workflow::Operation::Instance->get($id);

    $instance->current->cpu_time($cpu_sec) if $cpu_sec;
    $instance->current->max_memory($mem) if $mem;
    $instance->current->max_swap($swap) if $swap;

    $instance->completion();
}

sub _workflow_schedule_instance {
    my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
    my ($id, $dispatch_id) = @$arg;

    DEBUG "workflow schedule_instance";
    $heap->{changes}++;

    my $instance = Workflow::Operation::Instance->get($id);

    $instance->current->status('scheduled');
    $instance->current->dispatch_identifier($dispatch_id);
}

1;
