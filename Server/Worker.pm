
package Workflow::Server::Worker;

use strict;
use lib '/gscuser/eclark/lib';
use POE;
use POE::Component::IKC::Client;
use Workflow ();


our $kernel_name;

sub start {
    my ($class, $host, $port) = @_;

    $host ||= 'localhost';
    $port ||= 13424;

    $kernel_name = 'Worker' . $$;

    our $client = POE::Component::IKC::Client->spawn( 
        ip=>$host, 
        port=>$port,
        name=>$kernel_name,
        on_connect=>\&__build
    );

    $Storable::forgive_me=1;
    
    POE::Kernel->run();
}

sub __build {
    our $worker = POE::Session->create(
        inline_states => {
            _start => sub { 
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                $kernel->alias_set("worker");
                $kernel->call('IKC','publish','worker',[qw(execute)]);

                $kernel->yield('get_work');
            },
            execute => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($instance, $type, $input) = @$arg;
                
                $kernel->alarm_remove_all;

                my $status = 'done';
                my $output;
                eval {
                    $output = $type->execute(%{ $instance->input }, %$input);
                };
                if ($@) {
                    $status = 'crashed';
                }

                $kernel->post('IKC','post','poe://Hub/dispatch/end_work',[ $instance->id, $status, $output ]);
                $kernel->yield('disconnect');
            },
            disconnect => sub {
                $_[KERNEL]->post('IKC','shutdown');
            },
            get_work => sub {
                my ($kernel) = @_[KERNEL];

                $kernel->post(
                    'IKC','post','poe://Hub/dispatch/get_work',["poe://$kernel_name/worker/execute"]
                );
            }
        }
    );
}

1;
