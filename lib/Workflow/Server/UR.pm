package Workflow::Server::UR;

use strict;
use base 'Workflow::Server';
use POE qw(Component::IKC::Server Component::IKC::Client);
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
    my $class = shift;
    my %args = @_;

    _setup_client(%args);

    DEBUG "ur server starting on port " . $args{ur_port};
    POE::Component::IKC::Server->spawn(
        port => $args{ur_port}, name => 'UR'
    );
}

sub _setup_client {
    my %args = @_;
    my $ur_port = $args{ur_port};
    my $hub_port = $args{hub_port};

    $Storable::forgive_me = 1;

    DEBUG "ur process connecting to hub " . $hub_port;
    POE::Component::IKC::Client->spawn(
        ip         => 'localhost',
        port       => $hub_port,
        name       => 'UR',
        on_connect => sub { # $poe_kernel exported by POE
            _build($poe_kernel->get_active_session()->ID, $ur_port);
        }
    );
}

sub _build {
    my ($channel, $port_number) = @_;

    POE::Session->create(
        heap => {
            channel => $channel,
            port_number => $port_number,
            changes => 0,  ## this means possible changes, not that anything actually changed and needs to be synced.  For my purposes I don't care.
            unchanged_commits => 0,
        },
        inline_states => {
            _start    => \&_workflow_start,
            _stop     => \&_workflow_stop,
            unlock_me => sub { Workflow::Server->unlock('UR'); },

            sig_HUP      => \&_workflow_sig_HUP,
            register     => \&_workflow_register,
            unregister   => \&_workflow_unregister,
            output_relay => \&_workflow_output_relay,
            error_relay  => \&_workflow_error_relay,

            simple_start      => \&_workflow_simple_start,
            simple_resume     => \&_workflow_simple_resume,
            load              => \&_workflow_load,
            execute           => \&_workflow_execute,
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
    my ($class,$instance,$input) = @_;

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
        [qw(simple_start
            simple_resume
            load
            execute
            resume
            begin_instance
            end_instance
            finalize_instance
            schedule_instance
            quit)]
    );

    $kernel->sig('HUP','sig_HUP');

    $kernel->post('IKC','monitor',
            '*'=>{register=>'register', unregister=>'unregister'});

    $heap->{workflow_plans} = {};
    $heap->{workflow_executions} = {};
    $heap->{record} = Workflow::Service->create(port => $heap->{port_number});
    UR::Context->commit();

    $kernel->delay('commit', 30);
    $kernel->yield('unlock_me');
}

sub _workflow_stop {
    my ($heap) = @_[HEAP];

    DEBUG "workflow _stop";
    $heap->{record}->delete();
    UR::Context->commit();
}

sub _workflow_sig_HUP {
    my ($heap) = @_[HEAP];

    $heap->{record}->delete();
    UR::Context->commit();

    # NOTE: not calling sig_handled so this is still terminal
}

sub _workflow_simple_start {
    my ($kernel, $session, $arg) = @_[KERNEL, SESSION, ARG0];
    my ($arg2, $return) = @$arg;
    my ($xml, $input) = @$arg2;

    DEBUG "workflow simple_start";
    my $id = $kernel->call($session, 'load', [$xml]);
    $kernel->call($session,'execute',
            [$id, $input, $return, $return]);

    return $id;
}

sub _workflow_simple_resume {
    my ($kernel, $session, $arg) = @_[KERNEL, SESSION, ARG0];
    my ($arg2, $return) = @$arg;
    my ($id) = @$arg2;

    DEBUG "workflow simple_resume";
    $kernel->call($session, 'resume', [$id, $return, $return]);

    return $id;
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
    $kernel->post($heap->{channel}, 'shutdown');

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
        $heap->{unchanged_commits} = 0;
    } else {
        if(Workflow::DataSource::InstanceSchema->has_default_handle) {
            $heap->{unchanged_commits}++;
            if($heap->{unchanged_commits} > 2) {
                $heap->{unchanged_commits} = 0;
            }
        }
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

sub _workflow_load {
    my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
    my ($xml) = @$arg;

    DEBUG "workflow load";
    my $workflow = Workflow::Operation->create_from_xml($xml);
    $heap->{workflow_plans}->{$workflow->id} = $workflow;

    return $workflow->id;
}

sub _workflow_execute {
    my ($kernel, $session, $heap, $arg) = @_[KERNEL, SESSION, HEAP, ARG0];
    my ($id, $input, $output_dest, $error_dest) = @$arg;

    DEBUG "workflow execute";
    $heap->{changes}++;

    my $workflow = $heap->{workflow_plans}->{$id};
    my $executor = Workflow::Executor::Server->get();
    $workflow->set_all_executor($executor);

    my %opts = (
        input => $input
    );

    if($output_dest) {
        my $cb = $session->postback('output_relay', $output_dest);
        $opts{output_cb} = $cb;
    }
    if($error_dest) {
        my $cb = $session->postback('error_relay', $error_dest);
        $opts{error_cb} = $cb;
    }

    my $instance = $workflow->execute(%opts);

    if($instance->can('parent_execution_id') and
            exists($ENV{'WORKFLOW_PARENT_EXECUTION'})) {
        $instance->parent_execution_id($ENV{'WORKFLOW_PARENT_EXECUTION'});
    }

    $workflow->wait();

    $heap->{workflow_executions}->{$instance->id} = $instance;
    return $instance->id;
}

sub _workflow_resume {
    my ($kernel, $heap, $session, $arg) = @_[KERNEL, HEAP, SESSION, ARG0];
    my ($id, $output_dest, $error_dest) = @$arg;

    DEBUG "workflow resume";
    $heap->{changes}++;

    my @tree = Workflow::Operation::Instance->get(
        id => $id,
        -recurse => ['parent_instance_id', 'instance_id'],
    );
    my $instance = Workflow::Operation::Instance->get($id);

    my $executor = Workflow::Executor::Server->get();
    $instance->operation->set_all_executor($executor);

    if ($output_dest) {
        my $cb = $session->postback('output_relay', $output_dest);
        $instance->output_cb($cb);
    }
    if ($error_dest) {
        my $cb = $session->postback('error_relay', $error_dest);
        $instance->error_cb($cb);
    }

    if ($instance->is_done) {
        Workflow::Operation::InstanceExecution::Error->create(
            execution => $instance->current,
            error => "Cannot resume finished workflow"
        );
        $kernel->yield('error_relay', [$error_dest], [$instance]);

        return $instance->id;
    }

    $instance->resume();
    $instance->operation->wait();

    $heap->{workflow_executions}->{$instance->id} = $instance;
    return $instance->id;
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
    $kernel->post('IKC', 'post', $output_dest,
            [$instance->id, $instance->output, undef]);
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
    $kernel->post('IKC', 'post', $error_dest,
            [$instance->id, $instance->output, undef, \@errors]);
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
