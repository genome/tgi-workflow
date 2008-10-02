
package Workflow::Server::UR;

use strict;
use lib '/gscuser/eclark/lib';
use POE;
use POE::Component::IKC::Client;
use POE::Component::IKC::Server;
use Workflow ();

sub start {
    our $session = POE::Component::IKC::Client->spawn( 
        ip=>'localhost', 
        port=>13424,
        name=>'UR',
        on_connect=>\&__build
    );
    
    our $srv_session = POE::Component::IKC::Server->spawn(
        port => 13425, name => 'UR'
    );

    $Storable::forgive_me = 1;

    POE::Kernel->run();
}

sub __build {
    our $workflow = POE::Session->create(
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                $kernel->alias_set("workflow");
                $kernel->post('IKC','publish','workflow',
                    [qw(load execute resume begin_instance end_instance)]
                );
                
                $heap->{workflow_plans} = {};
                $heap->{workflow_executions} = {};

                $kernel->post('IKC','monitor','*'=>{register=>'conn',unregister=>'disc'});

                $kernel->delay('commit',120);
            },
            commit => sub {
                my ($kernel) = @_[KERNEL];

                print "Commit\n";
                UR::Context->commit();

                $kernel->delay('commit', 120);
            },
            conn => sub {
                my ($name,$real) = @_[ARG1,ARG2];
                print " Remote ", ($real ? '' : 'alias '), "$name connected\n";
            },
            disc => sub {
                my ($kernel,$name,$real) = @_[KERNEL,ARG1,ARG2];
                print " Remote ", ($real ? '' : 'alias '), "$name disconnected\n";

                if ($name eq 'Hub') {
                    $kernel->post('IKC','shutdown');
                }
            },
            load => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($xml) = @$arg;

                my $workflow = Workflow::Model->create_from_xml($xml);
                $heap->{workflow_plans}->{$workflow->id} = $workflow;
                
                return $workflow->id;
            },
            execute => sub {
                my ($kernel, $session, $heap, $arg) = @_[KERNEL,SESSION,HEAP,ARG0];
                my ($id,$input,$output_dest,$error_dest) = @$arg;
                
                my $workflow = $heap->{workflow_plans}->{$id};

                my $executor = Workflow::Executor::Server->create;
                $workflow->set_all_executor($executor);
 
                my $store = Workflow::Store::Db->create;

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
                print "Starting: " . $instance->id . "\n";
        
                $instance->sync;
            
                $workflow->wait;

                $heap->{workflow_executions}->{$instance->id} = $instance;
                return $instance->id;
            },
            resume => sub {
                my ($kernel, $heap, $session, $arg) = @_[KERNEL,HEAP,SESSION,ARG0];
                my ($id, $output_dest, $error_dest) = @$arg;
                
                my $instance = Workflow::Store::Db::Operation::Instance->get($id);

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
                my ($kernel, $heap, $xarg, $yarg) = @_[KERNEL,HEAP,ARG0,ARG1];
                my ($output_dest) = @$xarg;
                my ($instance) = @$yarg;

                $kernel->post('IKC','post',$output_dest,[$instance->id,$instance,$instance->current]); 
            },
            error_relay => sub {
                print "should relay error\n";

            },
            begin_instance => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($id) = @$arg;

                my $instance = Workflow::Store::Db::Operation::Instance->get($id);
                
                $instance->status('running');
                $instance->current->start_time(UR::Time->now);
            },
            end_instance => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
                my ($id,$status,$output) = @$arg;
                
                my $instance = Workflow::Store::Db::Operation::Instance->get($id);
                $instance->status($status);
                $instance->current->end_time(UR::Time->now);
                if ($status eq 'done') {
                    $instance->output({ %{ $instance->output }, %$output });
                }

                $instance->completion;
            },
        }
    );
}

sub dispatch {
    my ($class,$instance,$input) = @_;

    $instance->status('scheduled');
    
    POE::Kernel->post('IKC','post','poe://Hub/dispatch/add_work', [ $instance, $instance->operation->operation_type, $input ]);
}

1;
