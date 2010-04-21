
package Workflow::Server::Worker;

use strict;

use AnyEvent::Impl::POE;
use AnyEvent;
use POE;

use POE::Component::IKC::Client;
use Workflow::Server::Hub;
use Error qw(:try);

use Workflow ();

our $job_id;

sub start {
    my $class = shift;
    our $host = shift;
    our $port = shift;
    my $use_pid = shift;
    
    $host ||= 'localhost';
    $port ||= die 'no port number';

    if ($use_pid) {
        $job_id = 'P' . $$;
    } else {
        $job_id = $ENV{LSB_JOBID};
    }

    our $client = POE::Component::IKC::Client->spawn( 
        ip=>$host, 
        port=>$port,
        name=>'Worker',
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
                $kernel->call('IKC','publish','worker',[qw(execute disconnect)]);

                $kernel->yield('get_work');
            },
            execute => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($instance, $type, $input, $sc_flag) = @$arg;
                
                $kernel->alarm_remove_all;

                my $status = 'done';
                my $output;
                my $error_string;
                eval {
                    local $SIG{__DIE__} = sub {
                        my $m = Carp::longmess;
                        $m =~ s/^.+?\n//s;
                        die $_[0] . $m;
                    };

                    if ($sc_flag) {
                        $output = $type->shortcut(%{ $instance->input }, %$input);
                    } else {
                        $output = $type->execute(%{ $instance->input }, %$input);
                    }
                };
                if ($@ || !defined($output) ) {
                    print STDERR "Command module died or returned undef.\n";
                    if ($@) {
                        print STDERR $@;
                        $error_string = "$@";
                    } else {
                        $error_string = "Command module returned undef";
                    }
                    $status = 'crashed';
                } else {
                    UR::Context->commit();
                }

                $kernel->post('IKC','post','poe://Hub/dispatch/end_work',[$job_id, $kernel->ID, $instance->id, $status, $output, $error_string]);
                $kernel->yield('disconnect');
            },
            disconnect => sub {
                $_[KERNEL]->post('IKC','shutdown');
            },
            get_work => sub {
                my ($kernel) = @_[KERNEL];

                my $kernel_name = $kernel->ID;

                $kernel->post(
                    'IKC','post','poe://Hub/dispatch/get_work',[$job_id, $kernel->ID, "poe://$kernel_name/worker/execute"]
                );
            }
        }
    );
}

1;
