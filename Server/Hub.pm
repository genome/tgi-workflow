
package Workflow::Server::Hub;

use strict;
use base 'Workflow::Server';
use POE qw(Component::IKC::Server);

our $port_number = 13424;

use Workflow ();
use Sys::Hostname;

BEGIN {
    if (defined $ENV{WF_TRACE_HUB}) {
        eval 'sub evTRACE () { 1 }';
    } else {
        eval 'sub evTRACE () { 0 }';
    }
};

sub setup {
    my $class = shift;
    my %args = @_;
    
    our $server = POE::Component::IKC::Server->spawn(
        port => $port_number, name => 'Hub'
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
        heap => {
            periodic_check_time => 300,
            job_limit           => 500,
            job_count           => 0,
            dispatched          => {}, # keyed on lsf job id
            claimed             => {}, # keyed on remote kernel name
            failed              => {}, # keyed on instance id
            cleaning_up         => {}, # keyed on remote kernel name
            queue               => POE::Queue::Array->new()
        },
        inline_states => {
            _start => sub { 
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "dispatch _start\n";

                $kernel->alias_set("dispatch");
                $kernel->call('IKC','publish','dispatch',[qw(add_work get_work end_work quit)]);

                $kernel->post('IKC','monitor','*'=>{register=>'conn',unregister=>'disc'});
                
                $kernel->sig('USR1','sig_USR1');
                $kernel->sig('USR2','sig_USR2');
                
                $kernel->yield('unlock_me');
                
                $kernel->delay('periodic_check', $heap->{periodic_check_time});
            },
            sig_USR1 => sub {
                my ($kernel) = @_[KERNEL];
                
                $kernel->yield('check_jobs');
                $kernel->sig_handled();
            },
            sig_USR2 => sub {
                my ($kernel) = @_[KERNEL];
                
                $kernel->yield('start_jobs');
                $kernel->sig_handled();
            },
            unlock_me => sub {
                Workflow::Server->unlock('Hub');
            },
            quit => sub {
                my ($kernel) = @_[KERNEL];
                evTRACE and print "dispatch quit\n";

                $kernel->yield('quit_stage_2');

                return 1; # must return something here so IKC forwards the reply
            },
            quit_stage_2 => sub {
                my ($kernel) = @_[KERNEL];
                evTRACE and print "dispatch quit_stage_2\n";

                $kernel->alarm_remove_all;
                $kernel->post('IKC','shutdown');
            },
            conn => sub {
                my ($name,$real) = @_[ARG1,ARG2];
                evTRACE and print "dispatch conn ", ($real ? '' : 'alias '), "$name\n";
            },
            disc => sub {
                my ($kernel,$session,$heap,$remote_kernel,$real) = @_[KERNEL,SESSION,HEAP,ARG1,ARG2];
                evTRACE and print "dispatch disc ", ($real ? '' : 'alias '), "$remote_kernel\n";
                
                if (delete $heap->{cleaning_up}->{$remote_kernel} || exists $heap->{claimed}->{$remote_kernel}) {
                    $heap->{job_count}--;
                    
                    $kernel->delay('start_jobs',0);
                }
                
                if (exists $heap->{claimed}->{$remote_kernel}) {
                    my $payload = delete $heap->{claimed}->{$remote_kernel};
                    my ($instance, $type, $input) = @$payload;
                   
                    warn 'Blade failed on ' . $instance->id . ' ' . $instance->name . "\n";
                    $heap->{failed}->{$instance->id}++;

                    if ($heap->{failed}->{$instance->id} <= 5) {
                        $heap->{queue}->enqueue(200,$payload);
                    } else {
                        $kernel->yield('end_work',[-666,$remote_kernel,$instance->id,'crashed',{}]);
                    }
                }                
            },
            add_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($instance, $type, $input) = @$arg;
                evTRACE and print "dispatch add_work " . $instance->id . "\n";

                $heap->{failed}->{$instance->id} = 0;
                $heap->{queue}->enqueue(100,[$instance,$type,$input]);
                
                $kernel->delay('start_jobs',0);                
            },
            get_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id, $remote_kernel, $where) = @$arg;
                evTRACE and print "dispatch get_work $dispatch_id $where\n";

                if ($heap->{dispatched}->{$dispatch_id}) {
                    my $payload = delete $heap->{dispatched}->{$dispatch_id};
                    my ($instance, $type, $input) = @$payload;

                    $heap->{claimed}->{$remote_kernel} = $payload;

                    $kernel->post('IKC','post','poe://UR/workflow/begin_instance',[ $instance->id, $dispatch_id ]);
                    $kernel->post('IKC','post',$where,[$instance, $type, $input]);
                } else {
                    warn "dispatch get_work: unknown id $dispatch_id\n";
                }
            },
            end_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id, $remote_kernel, $id, $status, $output, $error_string) = @$arg;
                evTRACE and print "dispatch end_work $dispatch_id $id\n";

                delete $heap->{failed}->{$id};

                if ($remote_kernel) {
                    delete $heap->{claimed}->{$remote_kernel};
                    $heap->{cleaning_up}->{$remote_kernel} = 1;
                }

                $kernel->post('IKC','post','poe://UR/workflow/end_instance',[ $id, $status, $output, $error_string ]);
            },
            start_jobs => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "dispatch start_jobs " . $heap->{job_count} . ' ' . $heap->{job_limit} . "\n";
                
                while ($heap->{job_count} < $heap->{job_limit}) {
                    my ($priority, $queue_id, $payload) = $heap->{queue}->dequeue_next();
                    if (defined $priority) {
                        my ($instance, $type, $input) = @$payload;
                        $heap->{job_count}++;
                        
                        my $lsf_job_id = $kernel->call($_[SESSION],'lsf_bsub',$type->lsf_queue,$type->lsf_resource,$type->command_class_name,$instance->name);
                        $heap->{dispatched}->{$lsf_job_id} = $payload;

                        $kernel->post('IKC','post','poe://UR/workflow/schedule_instance',[$instance->id,$lsf_job_id]);

                        evTRACE and print "dispatch start_jobs $lsf_job_id\n";
                    } else {
                        last;
                    }
                }
            },
            lsf_bsub => sub {
                my ($kernel, $queue, $rusage, $command_class, $name) = @_[KERNEL, ARG0, ARG1, ARG2, ARG3];
                evTRACE and print "dispatch lsf_cmd\n";

                $queue ||= 'long';
                $rusage ||= 'rusage[tmp=100]';
                $name ||= 'worker';

                my $lsf_opts;

                $rusage =~ s/^\s+//;
                if ($rusage =~ /^-/) {
                    $lsf_opts = $rusage;
                } else {
                    $lsf_opts = '-R "' . $rusage . '"';
                }

                my $hostname = hostname;
                my $port = $port_number;

                my $namespace = (split(/::/,$command_class))[0];

                my @libs = UR::Util::used_libs();
                my $libstring = '';
                foreach my $lib (@libs) {
                    $libstring .= 'use lib "' . $lib . '"; ';
                }

                my $cmd = 'bsub -q ' . $queue . ' -m blades ' . $lsf_opts .
                    ' -J "' . $name . '" perl -e \'' . $libstring . 'use ' . $namespace . '; use ' . $command_class . '; use Workflow::Server::Worker; Workflow::Server::Worker->start("' . $hostname . '",' . $port . ')\'';

                evTRACE and print "dispatch lsf_cmd $cmd\n";

                my $bsub_output = `$cmd`;

                evTRACE and print "dispatch lsf_cmd $bsub_output";

                # Job <8833909> is submitted to queue <long>.
                $bsub_output =~ /^Job <(\d+)> is submitted to queue <(\w+)>\./;
                
                my $lsf_job_id = $1;
                return $lsf_job_id;
            },
            periodic_check => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "dispatch periodic_check\n";
                
                if (scalar keys %{ $heap->{dispatched} } > 0) {
                    $kernel->yield('check_jobs');
                }
                
                $kernel->delay('periodic_check', $heap->{periodic_check_time});                
            },
            check_jobs => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "dispatch check_jobs\n";
                
                my $number_restarted = 0;
                foreach my $lsf_job_id (keys %{ $heap->{dispatched} }) {
                    my $restart = 0;
                
                    if (my ($info,$events) = lsf_state($lsf_job_id)) {
                        $restart = 1 if ($info->{'Status'} eq 'EXIT');
                        
                        evTRACE and print "dispatch check_jobs <$lsf_job_id> suspended by user\n" 
                            if ($info->{'Status'} eq 'PSUSP');
                    } else {
                        $restart = 1;
                    }
                    
                    if ($restart) {
                        my $payload = delete $heap->{dispatched}->{$lsf_job_id};
                        my ($instance, $type, $input) = @$payload;

                        evTRACE and print 'dispatch check_jobs ' . $instance->id . ' ' . $instance->name . " vanished\n";
                        $heap->{job_count}--;
                        $heap->{failed}->{$instance->id}++;

                        if ($heap->{failed}->{$instance->id} <= 5) {
                            $heap->{queue}->enqueue(150,$payload);
                            
                            $number_restarted++;
                        } else {
                            $kernel->yield('end_work',[$lsf_job_id,undef,$instance->id,'crashed',{}]);
                        }
                    }
                }
                
                $kernel->delay('start_jobs',0) if ($number_restarted > 0);
            }
        }
    );

    $Storable::forgive_me=1;
}

sub lsf_state {
    my ($lsf_job_id) = @_;

    my $spool = `bjobs -l $lsf_job_id 2>&1`;
    return if ($spool =~ /Job <$lsf_job_id> is not found/);

    # this regex nukes the indentation and line feed
    $spool =~ s/\s{22}//gm; 

    my @eventlines = split(/\n/, $spool);
    shift @eventlines unless ($eventlines[0] =~ m/\S/);  # first line is white space
    
    my $jobinfoline = shift @eventlines;
    # sometimes the prior regex nukes the white space between Key <Value>
    $jobinfoline =~ s/(?<!\s{1})</ </g;

    my %jobinfo = ();
    # parse out a line such as
    # Key <Value>, Key <Value>, Key <Value>
    while ($jobinfoline =~ /(?:^|(?<=,\s{1}))(.+?)(?:\s+<(.*?)>)?(?=(?:$|;|,))/g) {
        $jobinfo{$1} = $2;
    }

    my @events = ();
    foreach my $el (@eventlines) {
        $el =~ s/(?<!\s{1})</ </g;

        my $time = substr($el,0,21,'');
        substr($time,-2,2,'');

        # see if we really got the time string
        if ($time !~ /\w{3}\s+\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}/) {
            # there's stuff we dont care about at the bottom, just skip it
            next;
        }

        my @entry = (
            $time,
            {}
        );

        while ($el =~ /(?:^|(?<=,\s{1}))(.+?)(?:\s+<(.*?)>)?(?=(?:$|;|,))/g) {
            $entry[1]->{$1} = $2;
        }
        push @events, \@entry;
    }


    return (\%jobinfo, \@events);
}

1;
