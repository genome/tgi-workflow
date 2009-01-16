
package Workflow::Server::UR;

use strict;
use base 'Workflow::Server';
use POE qw(Component::IKC::Server Component::IKC::Client);
use Workflow::Server::Hub;

our $store_db = 1;
our $port_number = 13425;

use Workflow ();

sub evTRACE () { 0 };

sub setup {
    my $class = shift;

    $class->setup_client(@_);
    
    our $srv_session = POE::Component::IKC::Server->spawn(
        port => $port_number, name => 'UR'
    );

}

sub setup_client {
    my $class = shift;
    my @connect_code = @_;

    $Storable::forgive_me = 1;

    our $session = POE::Component::IKC::Client->spawn( 
        ip         => 'localhost', 
        port       => $Workflow::Server::Hub::port_number,
        name       => 'UR',
        on_connect => sub {
            __build($poe_kernel->get_active_session()->ID,\@connect_code,\@_);
        } 
    );
}

sub __build {
    my $channel_id = shift;
    my $codebits = shift;
    my $args = shift;

    our $workflow = POE::Session->create(
        heap => {
            channel => $channel_id
        },
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
evTRACE and print "workflow _start\n";

                $kernel->alias_set("workflow");
                $kernel->post('IKC','publish','workflow',
                    [qw(simple_start load execute resume begin_instance end_instance quit eval)]
                );
                
                $heap->{workflow_plans} = {};
                $heap->{workflow_executions} = {};

                $kernel->post('IKC','monitor','*'=>{register=>'conn',unregister=>'disc'});

                $kernel->delay('commit',120);
                $kernel->yield('unlock_me');
            },
            _stop => sub {
evTRACE and print "workflow _stop\n";
            },
            unlock_me => sub {
                Workflow::Server->unlock('UR');
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
            quit => sub {
                my ($kernel,$session,$kill_hub_flag) = @_[KERNEL,SESSION,ARG0];
evTRACE and print "workflow quit\n";

                if (defined $kill_hub_flag && $kill_hub_flag) {
                    $kernel->post('IKC','call','poe://Hub/dispatch/quit',undef,'poe:quit_stage_2');
                } else {
                    $kernel->yield('quit_stage_2');
                }

            },
            quit_stage_2 => sub {
                my ($kernel,$session,$heap) = @_[KERNEL,SESSION,HEAP];
evTRACE and print "workflow quit_stage_2\n";

                $kernel->post($heap->{channel},'shutdown');

                $kernel->call($session,'commit');
                $kernel->alarm_remove_all;

                $kernel->post('IKC','shutdown');
            },
            commit => sub {
                my ($kernel) = @_[KERNEL];
evTRACE and print "workflow commit\n";

                if ($store_db) { 
                    UR::Context->commit();

                    $kernel->delay('commit', 120);
                }
            },
            conn => sub {
                my ($name,$real) = @_[ARG1,ARG2];
evTRACE and print "workflow conn ", ($real ? '' : 'alias '), "$name\n";
            },
            disc => sub {
                my ($kernel,$name,$real) = @_[KERNEL,ARG1,ARG2];
evTRACE and print "workflow disc ", ($real ? '' : 'alias '), "$name\n";

#                if ($name eq 'Hub') {
#                    $kernel->post('IKC','shutdown');
#                }
            },
            load => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($xml) = @$arg;
evTRACE and print "workflow load\n";

                my $workflow = Workflow::Operation->create_from_xml($xml);
                $heap->{workflow_plans}->{$workflow->id} = $workflow;
                
                return $workflow->id;
            },
            execute => sub {
                my ($kernel, $session, $heap, $arg) = @_[KERNEL,SESSION,HEAP,ARG0];
                my ($id,$input,$output_dest,$error_dest) = @$arg;
evTRACE and print "workflow execute\n";
                
                my $workflow = $heap->{workflow_plans}->{$id};

                my $executor = Workflow::Executor::Server->get;
                $workflow->set_all_executor($executor);
 
                my $store = $store_db ? Workflow::Store::Db->get : Workflow::Store::None->get;

                my %opts = (
                    input => $input,
                    store => $store
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

                $workflow->wait;

                $heap->{workflow_executions}->{$instance->id} = $instance;
                return $instance->id;
            },
            resume => sub {
                my ($kernel, $heap, $session, $arg) = @_[KERNEL,HEAP,SESSION,ARG0];
                my ($id, $output_dest, $error_dest) = @$arg;
evTRACE and print "workflow resume\n";
                
                my $instance = $store_db ? Workflow::Store::Db::Operation::Instance->get($id) : Workflow::Operation::Instance->get($id);

                my $executor = Workflow::Executor::Server->create;
                $instance->operation->set_all_executor($executor);                

                if ($output_dest) {
                    my $cb = $session->postback('output_relay',$output_dest);
                    $instance->output_cb($cb);
                }
                if ($error_dest) {
                    my $cb = $session->postback('error_relay',$error_dest);
                    $instance->error_cb($cb);
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

                $kernel->post('IKC','post',$output_dest,[$instance->id,$instance,$instance->current]); 
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
                
                $kernel->post('IKC','post',$error_dest,[$instance->id,$instance,$instance->current,\@errors]);
            },
            begin_instance => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($id,$dispatch_id) = @$arg;
evTRACE and print "workflow begin_instance\n";

                my $instance = $store_db ? Workflow::Store::Db::Operation::Instance->get($id) : Workflow::Operation::Instance->get($id);

                $instance->status('running');
                $instance->current->start_time(UR::Time->now);
                $instance->current->dispatch_identifier($dispatch_id);
            },
            end_instance => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($id,$status,$output,$error_string) = @$arg;
evTRACE and print "workflow end_instance\n";

                my $instance = $store_db ? Workflow::Store::Db::Operation::Instance->get($id) : Workflow::Operation::Instance->get($id);
                $instance->status($status);
                $instance->current->end_time(UR::Time->now);
                if ($status eq 'done') {
                    $instance->output({ %{ $instance->output }, %$output });
                } elsif ($status eq 'crashed') {
                    Workflow::Operation::InstanceExecution::Error->create(
                        execution => $instance->current,
                        error => $error_string
                    );
                }

                $instance->completion;
            },
            eval => sub {  ## this is somewhat dangerous to let people do
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($string,$array_context) = @$arg;
evTRACE and print "workflow eval\n";
                
                if ($array_context) {
                    my @result = eval($string);
                    if ($@) {
                        return [0,$@];
                    } else {
                        return [1,\@result];
                    }
                } else {
                    my $result = eval($string);
                    if ($@) {
                        return [0,$@];
                    } else {
                        return [1,$result];
                    }
                }
            }
        }
    );

    foreach my $code (@$codebits) {
        $code->();
    }
}

sub dispatch {
    my ($class,$instance,$input) = @_;

    $instance->status('scheduled');
    
    POE::Kernel->post('IKC','post','poe://Hub/dispatch/add_work', [ $instance, $instance->operation->operation_type, $input ]);
}

sub _util_error_walker {
    my $i = shift;
    my @errors = ($i->current->errors);
    if ($i->can('child_instances')) {
        foreach my $ci ($i->child_instances) {
            push @errors, _util_error_walker($ci);
        }
    }
    return @errors;
}

1;
