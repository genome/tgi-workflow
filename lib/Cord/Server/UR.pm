
package Cord::Server::UR;

use strict;
use base 'Cord::Server';
use POE qw(Component::IKC::Server Component::IKC::Client);
use Cord::Server::Hub;

use Cord ();

BEGIN {
    if (defined $ENV{WF_TRACE_UR}) {
        eval "sub evTRACE () { 1 }";
    } else {
        eval "sub evTRACE () { 0 }";
    }
};

sub setup {
    my $class = shift;
    my %args = @_;

    $class->setup_client(%args);
 
    print "ur server starting on port $args{ur_port}\n" if evTRACE;
    our $srv_session = POE::Component::IKC::Server->spawn(
        port => $args{ur_port}, name => 'UR'
    );

}

sub setup_client {
    my $class = shift;
    my %args = @_;

    $Storable::forgive_me = 1;

    print "ur process connecting to hub $args{hub_port}\n" if evTRACE;
    our $session = POE::Component::IKC::Client->spawn( 
        ip         => 'localhost', 
        port       => $args{hub_port},
        name       => 'UR',
        on_connect => sub {
            __build($poe_kernel->get_active_session()->ID, %args);
        } 
    );
}

sub __build {
    my $channel_id = shift;
    my %args = @_;

    my $port_number = $args{ur_port};

    our $workflow = POE::Session->create(
        heap => {
            channel => $channel_id,
            changes => 0,  ## this means possible changes, not that anything actually changed and needs to be synced.  For my purposes I don't care.
            unchanged_commits => 0
        },
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
evTRACE and print "workflow _start\n";

                $kernel->alias_set("workflow");
                $kernel->post('IKC','publish','workflow',
                    [qw(simple_start simple_resume load execute resume begin_instance end_instance finalize_instance schedule_instance quit eval)]
                );
                
                $heap->{workflow_plans} = {};
                $heap->{workflow_executions} = {};

                $kernel->sig('HUP','sig_HUP');

                $kernel->post('IKC','monitor','*'=>{register=>'conn',unregister=>'disc'});

                $heap->{record} = Cord::Service->create(port => $port_number);
                UR::Context->commit();

                $kernel->delay('commit',30);
                $kernel->yield('unlock_me');
            },
            _stop => sub {
                my ($heap) = @_[HEAP];
evTRACE and print "workflow _stop\n";
                
                $heap->{record}->delete();
                UR::Context->commit();
            },
            sig_HUP => sub {
                my ($heap) = @_[HEAP];
                
                $heap->{record}->delete();
                UR::Context->commit();
                ## not calling sig_handled so this is still terminal
            },
            unlock_me => sub {
                Cord::Server->unlock('UR');
            },
            simple_start => sub {
                my ($kernel, $session, $arg) = @_[KERNEL,SESSION,ARG0];
                my ($arg2, $return) = @$arg;
                my ($xml,$input) = @$arg2;
evTRACE and print "workflow simple_start\n";

                my $id = $kernel->call($session,'load',[$xml]);
                
                $kernel->call($session,'execute',[$id,$input,$return,$return]);
                
                return $id;
            },
            simple_resume => sub {
                my ($kernel, $session, $arg) = @_[KERNEL,SESSION,ARG0];
                my ($arg2, $return) = @$arg;
                my ($id) = @$arg2;
evTRACE and print "workflow simple_resume\n";

                $kernel->call($session,'resume',[$id,$return,$return]);
                
                return $id;
            },
            quit => sub {
                my ($kernel,$session,$kill_hub_flag) = @_[KERNEL,SESSION,ARG0];
evTRACE and print "workflow quit\n";

                if (defined $kill_hub_flag && $kill_hub_flag) {
                    $kernel->post('IKC','call','poe://Hub/dispatch/quit',undef,'poe:quit_stage_2');
                } else {
                    $kernel->yield('quit_stage_2');
                }
                return 1;
            },
            quit_stage_2 => sub {
                my ($kernel,$session,$heap) = @_[KERNEL,SESSION,HEAP];
evTRACE and print "workflow quit_stage_2\n";

                $kernel->post($heap->{channel},'shutdown');

                $kernel->call($session,'commit');
                $kernel->alarm_remove_all;
                $kernel->alias_remove('workflow');

                $kernel->post('IKC','shutdown');
            },
            commit => sub {
                my ($kernel, $heap) = @_[KERNEL,HEAP];

                    if ($heap->{changes} > 0) {
#                        evTRACE and print "workflow commit changes " . $heap->{changes} . "\n";
                        UR::Context->commit();
                        $heap->{changes} = 0;
                        $heap->{unchanged_commits} = 0;
                    } else {
                        if (Cord::DataSource::InstanceSchema->has_default_handle) {
                            $heap->{unchanged_commits}++;
                            if ($heap->{unchanged_commits} > 2) {
                                $heap->{unchanged_commits} = 0;
                            }
                        }
                    }
                $kernel->delay('commit', 30);
            },
            conn => sub {
                my ($name,$real) = @_[ARG1,ARG2];
evTRACE and print "workflow conn ", ($real ? '' : 'alias '), "$name\n";
            },
            disc => sub {
                my ($kernel,$name,$real) = @_[KERNEL,ARG1,ARG2];
evTRACE and print "workflow disc ", ($real ? '' : 'alias '), "$name\n";
            },
            load => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($xml) = @$arg;
evTRACE and print "workflow load\n";

                my $workflow = Cord::Operation->create_from_xml($xml);
                $heap->{workflow_plans}->{$workflow->id} = $workflow;
                
                return $workflow->id;
            },
            execute => sub {
                my ($kernel, $session, $heap, $arg) = @_[KERNEL,SESSION,HEAP,ARG0];
                my ($id,$input,$output_dest,$error_dest) = @$arg;
evTRACE and print "workflow execute\n";
               
                $heap->{changes}++;
 
                my $workflow = $heap->{workflow_plans}->{$id};

                my $executor = Cord::Executor::Server->get;
                $workflow->set_all_executor($executor);
 
                my %opts = (
                    input => $input
                );

                if ($output_dest) {
                    my $cb = $session->postback('output_relay',$output_dest);
                    $opts{output_cb} = $cb;
                }
                if ($error_dest) {
                    my $cb = $session->postback('error_relay',$error_dest);
                    $opts{error_cb} = $cb;
                }

                my $instance = $workflow->execute(%opts);

                if ($instance->can('parent_execution_id') && exists $ENV{'WORKFLOW_PARENT_EXECUTION'}) {
                    $instance->parent_execution_id($ENV{'WORKFLOW_PARENT_EXECUTION'});
                }

                $workflow->wait;

                $heap->{workflow_executions}->{$instance->id} = $instance;
                return $instance->id;
            },
            resume => sub {
                my ($kernel, $heap, $session, $arg) = @_[KERNEL,HEAP,SESSION,ARG0];
                my ($id, $output_dest, $error_dest) = @$arg;
evTRACE and print "workflow resume\n";

                $heap->{changes}++;
                
                    my @tree = Cord::Operation::Instance->get(
                        id => $id,
                        -recurse => ['parent_instance_id','instance_id']
                    );
                
                my $instance = Cord::Operation::Instance->get($id);

                my $executor = Cord::Executor::Server->get;
                $instance->operation->set_all_executor($executor);                

                if ($output_dest) {
                    my $cb = $session->postback('output_relay',$output_dest);
                    $instance->output_cb($cb);
                }
                if ($error_dest) {
                    my $cb = $session->postback('error_relay',$error_dest);
                    $instance->error_cb($cb);
                }

                if ($instance->is_done) {
                    Cord::Operation::InstanceExecution::Error->create(
                        execution => $instance->current,
                        error => "Cannot resume finished workflow"
                    );
                    
                    $kernel->yield('error_relay',[$error_dest],[$instance]);

                    return $instance->id;
                }
                
                $instance->resume();
                $instance->operation->wait();
                
                $heap->{workflow_executions}->{$instance->id} = $instance;
                
                return $instance->id;
            },
            output_relay => sub {
                my ($kernel, $session, $heap, $xarg, $yarg) = @_[KERNEL,SESSION,HEAP,ARG0,ARG1];
                my ($output_dest) = @$xarg;
                my ($instance) = @$yarg;
evTRACE and print "workflow output_relay\n";

                $instance->output_cb(undef);
                $instance->error_cb(undef);
                $kernel->refcount_decrement($session->ID,'anon_event');
                $kernel->refcount_decrement($session->ID,'anon_event');

                # undef hole is where $instance->current was.  removing that from the return set.
                $kernel->post('IKC','post',$output_dest,[$instance->id,$instance->output,undef]); 
            },
            error_relay => sub {
                my ($kernel, $session, $heap, $xarg, $yarg) = @_[KERNEL,SESSION,HEAP,ARG0,ARG1];
                my ($error_dest) = @$xarg;
                my ($instance) = @$yarg;
evTRACE and print "workflow error_relay\n";

                $instance->output_cb(undef);
                $instance->error_cb(undef);
                $kernel->refcount_decrement($session->ID,'anon_event');
                $kernel->refcount_decrement($session->ID,'anon_event');

                my @errors = _util_error_walker($instance);
                
                $kernel->post('IKC','post',$error_dest,[$instance->id,$instance->output,undef,\@errors]);
            },
            begin_instance => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($id,$dispatch_id) = @$arg;
evTRACE and print "workflow begin_instance\n";

                $heap->{changes}++;

                my $instance = Cord::Operation::Instance->get($id);

                $instance->status('running');
                $instance->current->start_time(Cord::Time->now);
                $instance->current->dispatch_identifier($dispatch_id);
            },
            end_instance => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($id,$status,$output,$error_string,$metrics) = @$arg;
evTRACE and print "workflow end_instance\n";

                $heap->{changes}++;

                my $instance = Cord::Operation::Instance->get($id);
                $instance->status($status);
                $instance->current->end_time(Cord::Time->now);

                while (my ($k,$v) = each(%$metrics)) {
                    $instance->current->add_metric(name => $k, value => $v);
                }
                if ($status eq 'done') {
                    $instance->output({ %{ $instance->output }, %$output });
                } elsif ($status eq 'crashed') {
                    Cord::Operation::InstanceExecution::Error->create(
                        execution => $instance->current,
                        error => $error_string
                    );
                }
            },
            finalize_instance => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($id, $cpu_sec, $mem, $swap) = @$arg;
evTRACE and print "workflow finalize_instance $id $cpu_sec $mem $swap\n";

                $heap->{changes}++;

                my $instance = Cord::Operation::Instance->get($id);

                $instance->current->cpu_time($cpu_sec) if $cpu_sec;
                $instance->current->max_memory($mem) if $mem;
                $instance->current->max_swap($swap) if $swap;

                $instance->completion;
            },
            'schedule_instance' => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($id,$dispatch_id) = @$arg;
evTRACE and print "workflow schedule_instance\n";

                $heap->{changes}++;

                my $instance = Cord::Operation::Instance->get($id);

                $instance->current->status('scheduled');
                $instance->current->dispatch_identifier($dispatch_id);
            },
        }
    );
}

sub dispatch {
    my ($class,$instance,$input) = @_;

    $instance->status('scheduled');
    
    my $try_shortcut_first = $instance->operation->operation_type->can('shortcut') ? 1 : 0;

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

1;
