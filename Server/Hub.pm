
package Workflow::Server::Hub;

use strict;
use base 'Workflow::Server';
use POE qw(Component::IKC::Server);

use Workflow ();
use Sys::Hostname;

sub setup {
    my $class = shift;
    my %args = @_;
    
    our $server = POE::Component::IKC::Server->spawn(
        port => 13424, name => 'Hub'
    );

    our $printer = POE::Session->create(
        inline_states => {
            _start => sub { 
                my ($kernel) = @_[KERNEL];
                $kernel->alias_set("printer");
                $kernel->call('IKC','publish','printer',[qw(stdout stderr)]);
            },
            stdout => sub {
                my ($arg) = @_[ARG0];
                
                print "$arg\n";
            },
            stderr => sub {
                my ($arg) = @_[ARG0];
                
                print STDERR "$arg\n";
            }
        }
    );
    
    our $dispatch = POE::Session->create(
        inline_states => {
            _start => sub { 
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                $kernel->alias_set("dispatch");
                $kernel->call('IKC','publish','dispatch',[qw(add_work get_work end_work quit)]);

                $heap->{queue} = POE::Queue::Array->new();
                $heap->{claimed} = {};
                $heap->{failed} = {};

                $kernel->post('IKC','monitor','*'=>{register=>'conn',unregister=>'disc'});
            },
            quit => sub {
                my ($kernel) = @_[KERNEL];

                $kernel->post('IKC','shutdown');
            },
            conn => sub {
                my ($name,$real) = @_[ARG1,ARG2];
#                print " Remote ", ($real ? '' : 'alias '), "$name connected\n";
            },
            disc => sub {
                my ($kernel,$session,$heap,$name,$real) = @_[KERNEL,SESSION,HEAP,ARG1,ARG2];
#                print " Remote ", ($real ? '' : 'alias '), "$name disconnected\n";
                
                if (exists $heap->{claimed}->{$name}) {
                    my $payload = $heap->{claimed}->{$name};
                    delete $heap->{claimed}->{$name};
                    
#                    print 'Blade failed: ' . $payload->[0]->id . ' ' . $payload->[0]->name . "\n";

                    $heap->{failed}->{$payload->[0]->id}++;

                    if ($heap->{failed}->{$payload->[0]->id} <= 5) {
                        $heap->{queue}->enqueue(200,$payload);

                        my $cmd = $kernel->call($session,'lsf_cmd');
                        $kernel->post($session,'system_cmd', $cmd);
                    } else {
                        $kernel->post($session,'end_work',[$name,$payload->[0]->id,'crashed',{}]);
                    }
                }
            },
            add_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($instance, $type, $input) = @$arg;

#                print "Add  Work: " . $instance->id . " " . $instance->name . "\n";

                $heap->{failed}->{$instance->id} = 0;
                $heap->{queue}->enqueue(100,[$instance,$type,$input]);

                my $cmd = $kernel->call($_[SESSION],'lsf_cmd');
                $kernel->post($_[SESSION],'system_cmd', $cmd);
            },
            get_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($where, $remote_name) = @$arg;

                my ($priority, $queue_id, $payload) = $heap->{queue}->dequeue_next();
                if (defined $priority) {
                    my ($instance, $type, $input) = @$payload;
#                    print 'Exec Work: ' . $instance->id . ' ' . $instance->name . "\n";

                    $heap->{claimed}->{$remote_name} = $payload;

                    $kernel->post('IKC','post','poe://UR/workflow/begin_instance',[ $instance->id ]);
                    $kernel->post('IKC','post',$where, [$instance, $type, $input]);
                }
            },
            end_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($remote_name, $id, $status, $output, $error_string) = @$arg;

                delete $heap->{claimed}->{$remote_name};
                delete $heap->{failed}->{$id};

                $kernel->post('IKC','post','poe://UR/workflow/end_instance',[ $id, $status, $output, $error_string ]);
            },
            lsf_cmd => sub {
                my ($kernel, $queue, $rusage) = @_[KERNEL, ARG0, ARG1];

                $queue ||= 'long';
                $rusage ||= ' -R "rusage[tmp=100]"';

                my $hostname = hostname;
                my $port = 13424;

                my $namespace = 'Genome';

                my $cmd = 'bsub -q ' . $queue . ' -N -u "' . $ENV{USER} . '@genome.wustl.edu" -m blades' . $rusage .
                    ' perl -e \'use above; use ' . $namespace . '; use Workflow::Server::Worker; Workflow::Server::Worker->start("' . $hostname . '",' . $port . ')\'';

                return $cmd;
            },
            system_cmd => sub {
                my ($cmd) = @_[ARG0];
    
                system($cmd);
            }
        }
    );

    $Storable::forgive_me=1;
}

1;
