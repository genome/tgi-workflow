
package Workflow::Server::Hub;

use strict;
use base 'Workflow::Server';
use POE qw(Component::IKC::Server Wheel::FollowTail);

use Workflow ();
use Sys::Hostname;
use Text::CSV;

my %JOB_STAT = (
    NULL => 0x00,
    PEND => 0x01,
    PSUSP => 0x02,
    RUN => 0x04,
    SSUSP => 0x08,
    USUSP => 0x10,
    EXIT => 0x20,
    DONE => 0x40,
    PDONE => 0x80,
    PERR => 0x100,
    WAIT => 0x200,
    UNKWN => 0x10000
);

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

    print "hub server starting on port $args{hub_port}\n" if evTRACE; 
    our $server = POE::Component::IKC::Server->spawn(
        port => $args{hub_port}, name => 'Hub'
    );

    my $port_number = $args{hub_port};

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
    
    our $watchdog = POE::Session->create(
        heap => {
            watchlist => POE::Queue::Array->new()
        },
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "watchdog _start\n";

                $kernel->alias_set("watchdog");
                $kernel->call('IKC','publish','watchdog',[qw(create delete)]);
            },
            _stop => sub {
                evTRACE and print "watchdog _stop\n";
            },
            create => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id,$duration) = @$arg;
                
                evTRACE and print "watchdog create $dispatch_id $duration\n";
                
                my $start_time = time;
                $heap->{watchlist}->enqueue($start_time + $duration, $dispatch_id);
                
                $heap->{alarm_id} = $kernel->alarm(check => $heap->{watchlist}->get_next_priority);
                return 1;
            },
            delete => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id) = @$arg;

                evTRACE and print "watchdog delete $dispatch_id\n";
            
                $heap->{watchlist}->remove_items(sub {
                    shift == $dispatch_id
                });
                
                if ($heap->{watchlist}->get_item_count) {
                    $heap->{alarm_id} = $kernel->alarm(check => $heap->{watchlist}->get_next_priority);
                } else {
                    $kernel->alarm_remove_all();
                }
                return 1;
            },
            check => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "watchdog check\n";
                
                while ($heap->{watchlist}->get_next_priority && $heap->{watchlist}->get_next_priority <= time) {
                    my ($priority, $id, $dispatch_id) = $heap->{watchlist}->dequeue_next;
                    
                    $kernel->yield('kill_job',$dispatch_id);
                }

                if ($heap->{watchlist}->get_item_count) {
                    $heap->{alarm_id} = $kernel->alarm(check => $heap->{watchlist}->get_next_priority);
                }
            },
            kill_job => sub {
                my ($kernel,$heap,$dispatch_id) = @_[KERNEL, HEAP, ARG0];
                evTRACE and print "watchdog kill_job $dispatch_id\n";
                
                system('bkill ' . $dispatch_id);
            }
        }
    );

    our $lsftail = POE::Session->create(
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "lsftail _start\n";

                $kernel->alias_set("lsftail");
                $kernel->call('IKC','publish','lsftail',[qw(add_watcher delete_watcher quit)]);

                my $filename = "/usr/local/lsf/work/gsccluster1/logdir/lsb.acct";
                my $newfilename = "/usr/local/lsfmaster/work/gsccluster1/logdir/lsb.acct";

                if (-e $newfilename && -r _) {
                    $filename = $newfilename;
                }

                $heap->{monitor} = POE::Wheel::FollowTail->new(
                    Filename => $filename,
                    InputEvent => 'handle_input',
                    ResetEvent => 'handle_reset',
                    ErrorEvent => 'handle_error'
                );
                $heap->{csv} = Text::CSV->new({
                    sep_char => ' ',
                });
                
                $heap->{watchers} = {};
                $heap->{alarms} = {};
            },
            _stop => sub {
                evTRACE and print "lsftail _stop\n";
            },
            add_watcher => sub {
                my ($heap,$kernel,$params) = @_[HEAP,KERNEL,ARG0];
                my ($job_id,$action) = ($params->{job_id},$params->{action});
                evTRACE and print "lsftail add_watcher $job_id\n";
                
                $heap->{watchers}{$job_id} = $action;
            },
            delete_watcher => sub {
                my ($kernel, $heap,$params) = @_[KERNEL,HEAP,ARG0];
                my $job_id = $params->{job_id};
                evTRACE and print "lsftail delete_watcher $job_id\n";
            
                delete $heap->{watchers}{$job_id};
                my $aid = delete $heap->{alarms}{$job_id};
                
                if ($aid) {
                    $kernel->alarm_remove($aid);
                }
            },
            skip_watcher => sub {
                my ($kernel, $heap, $params) = @_[KERNEL,HEAP,ARG0];
                my $job_id = $params->{job_id};
                my $seconds = $params->{seconds};
                evTRACE and print "lsftail skip_watcher $job_id $seconds\n";
            
                if (exists $heap->{watchers}{$job_id}) {
                    my $id = $kernel->delay_set('skip_it',$seconds,$job_id);
                    $heap->{alarms}{$job_id} = $id;
                }
            },
            quit => sub {
                my ($heap) = $_[HEAP];
                evTRACE and print "lsftail quit\n";
                
                delete $heap->{monitor};
            },
            handle_input => sub {
                my ($kernel, $heap, $line) = @_[KERNEL,HEAP,ARG0];

                $heap->{csv}->parse($line);
                my @fields = $heap->{csv}->fields();

                $kernel->yield('event_' . $fields[0], $line, \@fields);
            },
            handle_reset => sub {

            },
            handle_error => sub {
                my ($heap, $operation, $errnum, $errstr, $wheel_id) = @_[HEAP, ARG0..ARG3];
                warn "Wheel $wheel_id: $operation error $errnum: $errstr\n";
                delete $heap->{monitor};
            },
            skip_it => sub {
                my ($kernel, $heap, $job_id) = @_[KERNEL,HEAP,ARG0];
                evTRACE and print "lsftail skip_it $job_id\n";
                
                return unless exists $heap->{watchers}{$job_id};
                
                $heap->{watchers}{$job_id}->();
                
                $kernel->call($_[SESSION], 'delete_watcher',{job_id => $job_id});
            },
            event_JOB_FINISH => sub {
                my ($kernel,$heap, $line,$fields) = @_[KERNEL,HEAP, ARG0,ARG1];
                my $job_id = $fields->[3];

                if (exists $heap->{watchers}{$job_id}) {

                evTRACE and print "lsftail event_JOB_FINISH $job_id\n";

                    my $offset = $fields->[22];
                    $offset += $fields->[$offset+23];
                    my $job_stat_code = $fields->[$offset + 24];

                    my $job_status;
                    while (my ($k,$v) = each(%JOB_STAT)) {
                        if ($job_stat_code & $v) {
                            if (!defined $job_status ||
                                $JOB_STAT{$job_status} < $v) {
                                $job_status = $k;
                            }
                        }
                    }
                    
                    $heap->{watchers}{$job_id}->(
                        $job_id, $job_status, $job_stat_code,
                        @{ $fields }[$offset+28,$offset+29,$offset+54,$offset+55]
                    );
                    
                    $kernel->call($_[SESSION], 'delete_watcher',{job_id => $job_id});
                }

            },
        }
    );
    
    our $dispatch = POE::Session->create(
        heap => {
            periodic_check_time => 300,
            job_limit           => 500,
            job_count           => 0,
            fork_limit          => 1,
            fork_count          => 0,
            dispatched          => {}, # keyed on lsf job id
            claimed             => {}, # keyed on remote kernel name
            failed              => {}, # keyed on instance id
            cleaning_up         => {}, # keyed on remote kernel name
            finalizable         => {}, # keyed on instance id
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
                $kernel->sig('CHLD','sig_CHLD');
                $kernel->sig('HUP','sig_HUP_INT_TERM');
                $kernel->sig('INT','sig_HUP_INT_TERM');
                $kernel->sig('TERM','sig_HUP_INT_TERM');
                $kernel->yield('unlock_me');
                
                $kernel->delay('periodic_check', $heap->{periodic_check_time});
            },
            _stop => sub {
                evTRACE and print "dispatch _stop\n";

                ## breaking down.
            },
            sig_HUP_INT_TERM => sub {
                my ($kernel) = @_[KERNEL];
                evTRACE and print "dispatch sig_HUP_INT_TERM\n";

                $kernel->call($_[SESSION],'close_out');

                exit;
                $kernel->sig_handled();
            },
            sig_USR1 => sub {
                my ($kernel) = @_[KERNEL];
                
                $kernel->yield('check_jobs');
                $kernel->sig_handled();
            },
            sig_USR2 => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                
                $kernel->delay('start_jobs',0);

                my @entire_queue = $heap->{queue}->peek_items(sub { 1 });
                print STDERR Data::Dumper->new([$heap,\@entire_queue],['heap','queue'])->Dump . "\n";

                $kernel->sig_handled();
            },
            sig_CHLD => sub {
                my ($heap, $kernel, $pid, $child_error) = @_[HEAP, KERNEL, ARG1, ARG2];
                $heap->{fork_count}--;
                $kernel->delay('start_jobs',0);

                if (exists $heap->{dispatched}->{'P' . $pid}) {
                    $heap->{job_count}--;

                    my $payload = delete $heap->{dispatched}->{'P' . $pid};
                    $payload->{shortcut_flag} = 0;

                    $kernel->yield('add_work', $payload);
                }

                evTRACE and print "dispatch sig_CHLD $pid $child_error\n";
            },
            close_out => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "dispatch close_out\n";

                ### clear queue
                evTRACE and print "dispatch close_out clear queue\n";
                $heap->{queue}->remove_items(sub { 1; });

                ### clear pending jobs               
                evTRACE and print "dispatch close_out bkill pending\n";
                foreach my $id (keys %{ $heap->{'dispatched'} }) {
                    delete $heap->{'dispatched'}->{$id};

                    system("bkill $id");
                }

                ### clear running jbos
                evTRACE and print "dispatch close_out bkill running\n";
                foreach my $remote_kernel (keys %{ $heap->{claimed} }) {
                    my $payload = delete $heap->{claimed}->{$remote_kernel};

                    system('bkill ' . $payload->{dispatch_id});
                }
            },
            unlock_me => sub {
                Workflow::Server->unlock('Hub');
            },
            quit => sub {
                my ($kernel) = @_[KERNEL];
                evTRACE and print "dispatch quit\n";

                $kernel->post('lsftail','quit');
                $kernel->yield('quit_stage_2');

                return 1; # must return something here so IKC forwards the reply
            },
            quit_stage_2 => sub {
                my ($kernel) = @_[KERNEL];
                evTRACE and print "dispatch quit_stage_2\n";

                $kernel->alarm_remove_all;
                $kernel->alias_remove('dispatch');
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
                    my $instance = $payload->{instance};
                    my $sc = $payload->{shortcut_flag};
                    
                    warn 'Blade failed on ' . $payload->{dispatch_id} . ' ' . $instance->id . ' ' . $instance->name . "\n";

                    if ($sc) {
                        $payload->{shortcut_flag} = 0;
                    } else {
                        $heap->{failed}->{$instance->id}++;
                    }

                    if ($heap->{failed}->{$instance->id} <= 1) {
                        $heap->{queue}->enqueue(200,$payload);
                    } else {
                        $kernel->yield('end_work',[-666,$remote_kernel,$instance->id,'crashed',{}]);
                    }
                }                
            },
            add_work => sub {
                my ($kernel, $heap, $params) = @_[KERNEL, HEAP, ARG0];
                my $instance = $params->{instance};
                evTRACE and print "dispatch add_work " . $instance->id . "\n";

                $heap->{failed}->{$instance->id} = 0;
                $heap->{queue}->enqueue(100,$params);
                
                $kernel->delay('start_jobs',0);                
            },
            get_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id, $remote_kernel, $where) = @$arg;
                evTRACE and print "dispatch get_work $dispatch_id $where\n";

                if ($heap->{dispatched}->{$dispatch_id}) {
                    my $payload = delete $heap->{dispatched}->{$dispatch_id};
                    my ($instance, $type, $input, $sc) = @{ $payload }{qw/instance operation_type input shortcut_flag/};
                    $payload->{dispatch_id} = $dispatch_id;

                    $heap->{claimed}->{$remote_kernel} = $payload;

                    $kernel->post('IKC','post','poe://UR/workflow/begin_instance',[ $instance->id, $dispatch_id ]);
                    $kernel->post('IKC','post',$where,[$instance, $type, $input, $sc, $payload->{out_log}, $payload->{err_log}]);
                } else {
                    warn "dispatch get_work: unknown id $dispatch_id\n";
                    $kernel->post('IKC','post',"poe://$remote_kernel/worker/disconnect");
                }
            },
            end_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id, $remote_kernel, $id, $status, $output, $error_string, $metrics) = @$arg;
                evTRACE and print "dispatch end_work $dispatch_id $id\n";

                delete $heap->{failed}->{$id};

                my $was_shortcutting = 0;
                my $sc;

                if ($remote_kernel) {
                    my $payload = delete $heap->{claimed}->{$remote_kernel};
                    if ($payload) {
                        $sc = $payload->{shortcut_flag};
                        if ($sc && !defined $output) {
                            $was_shortcutting = 1;
                            $payload->{shortcut_flag} = 0;
                            $kernel->yield('add_work',$payload);
                        }
                    }
                    
                    $heap->{cleaning_up}->{$remote_kernel} = 1;
                }

                $kernel->post('IKC','post','poe://UR/workflow/end_instance',[ $id, $status, $output, $error_string, $metrics ])
                    unless $was_shortcutting;

                $heap->{finalizable}{$id} = $dispatch_id;

                if ($remote_kernel && !$sc) {
                    $kernel->post('lsftail','skip_watcher',{job_id => $dispatch_id, seconds => 60});
                } else {
                    $kernel->yield('finalize_work',[$id], []) unless $was_shortcutting;
                }
            },
            finalize_work => sub {
                my ($kernel,$heap,$create_arg,$called_arg) = @_[KERNEL,HEAP,ARG0,ARG1];
                my ($id) = @$create_arg;
                return unless exists $heap->{finalizable}{$id};
                evTRACE and print "dispatch finalize_work $id\n";

                if (@{ $called_arg } && $called_arg->[0] eq $heap->{finalizable}{$id}) {
                    my ($user_sec,$sys_sec,$mem,$swap) = @{ $called_arg }[3,4,5,6];
                    
                    $kernel->post('IKC','post','poe://UR/workflow/finalize_instance',[ $id, ($user_sec+$sys_sec), $mem, $swap ]);
                } else {
                    $kernel->post('IKC','post','poe://UR/workflow/finalize_instance',[ $id ]);
                }
            },
            start_jobs => sub {
                my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
                evTRACE and print "dispatch start_jobs " . $heap->{job_count} . ' ' . $heap->{job_limit} . "\n";
                
                my @requeue = ();
                while ($heap->{job_count} < $heap->{job_limit}) {
                    my ($priority, $queue_id, $payload) = $heap->{queue}->dequeue_next();
                    last unless (defined $priority);
                    my $lsf_job_id;
                    if ($payload->{shortcut_flag}) {
                        if ($heap->{fork_count} >= $heap->{fork_limit}) {
                            push @requeue, $payload;
                            next;
                        }
                        
                        $lsf_job_id = $kernel->call($_[SESSION],'fork_worker',
                            $payload->{operation_type}->command_class_name, $payload->{out_log}, $payload->{err_log}
                        );
                        $heap->{fork_count}++;
                        $heap->{job_count}++;
                    } else {
                        # $resource is a Workflow::Resource object
                        my $resource = $payload->{operation_type}->resource;
                        my $queue = $resource->queue || $payload->{operation_type}->lsf_queue || 'long';
                        my $name = $payload->{instance}->name || 'worker';


                        my $namespace = (split(/::/, $payload->{operation_type}->command_class_name))[0];

                        my $libstring = '';
                        foreach my $lib (reverse UR::Util::used_libs()) {
                            $libstring .= 'use lib "' . $lib . '"; ';
                        }

                        my $command = sprintf("annotate-log $^X -e '%s use %s; use %s; use Workflow::Server::Worker; Workflow::Server::Worker->start(\"%s\", %s)'", $libstring, $namespace, $payload->{operation_type}->command_class_name, hostname, $port_number);
                        my $stdout = $payload->{out_log};
                        my $stderr = $payload->{err_log};
                       
                        # parse the stdout & stderr paths out of a bare lsf resource requests if needed.
                        my $lsf_resource = $payload->{operation_type}->lsf_resource;
                        if ($lsf_resource =~ /-o/) {
                            ($stdout) = ($lsf_resource =~ /-o ([^\s]*)/);
                        }
                        if ($lsf_resource =~ /-e/) {
                            ($stderr) = ($lsf_resource =~ /-e ([^\s]*)/);
                        }

                        my $job = Workflow::Dispatcher::Job->create(
                            resource => $resource,
                            command => $command,
                            group => "/workflow-worker2",
                            queue => $queue,
                            name => $name
                        );

                        $job->project($payload->{operation_type}->lsf_project) if (defined $payload->{operation_type}->lsf_project);
                        $job->stdout($stdout) if (defined $stdout);
                        $job->stderr($stderr) if (defined $stderr);

                        my $dispatcher = Workflow::Dispatcher->get();

                        evTRACE and print "start_jobs calling command: " . $dispatcher->get_command($job);

                        $lsf_job_id = $dispatcher->execute($job);

                        if ($lsf_job_id) {
                            $heap->{job_count}++;
                        
                            my $cb = $session->postback(
                                'finalize_work', $payload->{instance}->id
                            );

                            $kernel->post('lsftail','add_watcher',{job_id => $lsf_job_id, action => $cb});
                        }

                    }

                    if ($lsf_job_id) {
                        $heap->{dispatched}->{$lsf_job_id} = $payload;

                        $kernel->post('IKC','post','poe://UR/workflow/schedule_instance',[$payload->{instance}->id,$lsf_job_id]);

                        evTRACE and print "dispatch start_jobs submitted $lsf_job_id " . $payload->{shortcut_flag} . "\n";
                    } else {
                        evTRACE and print "dispatch failed to start job, will retry on next cycle\n";
                    }
                }
                
                foreach my $payload (@requeue) {
                    $heap->{queue}->enqueue(125,$payload);
                }
            },
            fork_worker => sub {
                my ($kernel, $command_class, $stdout_file, $stderr_file) = @_[KERNEL, ARG0, ARG1, ARG2];
                evTRACE and print "dispatch fork_worker $command_class $stdout_file $stderr_file\n";

                my $hostname = hostname;
                my $port = $port_number;

                my $namespace = (split(/::/,$command_class))[0];

                my @libs = UR::Util::used_libs();
                my $libstring = '';
                foreach my $lib (reverse @libs) {
                    $libstring .= 'use lib "' . $lib . '"; ';
                }

                my @cmd = (
                    'annotate-log',
                    $^X,
                    '-e',
                    $libstring . 'use ' . $namespace . '; use ' . $command_class . '; use Workflow::Server::Worker; Workflow::Server::Worker->start("' . $hostname . '",' . $port . ',2)'
                );

                my $pid;
                {
                    if ($pid = fork()) {
                        # parent
                        evTRACE and print "dispatch fork_worker " . join(' ', @cmd) . "\n";

                        return 'P' . $pid;
                    } elsif (defined $pid) {
                        # child
                        evTRACE and print "dispatch fork_worker started $$\n";

                        if ($stdout_file) {
                            open STDOUT, '>>', $stdout_file;
                        }

                        if ($stderr_file) {
                            open STDERR, '>>', $stderr_file;
                        }

                        exec @cmd;
                    } else {
                    
                    }
                }
            },
            periodic_check => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                
                if (scalar keys %{ $heap->{dispatched} } > 0) {
                    $kernel->yield('check_jobs');
                }
                
                $kernel->delay('periodic_check', $heap->{periodic_check_time});                
            },
            check_jobs => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                
                my $number_restarted = 0;
                foreach my $lsf_job_id (keys %{ $heap->{dispatched} }) {
                    next if ($lsf_job_id =~ /^P/);
                    my $restart = 0;
               
                    my $info = lsf_state($lsf_job_id); 
                    if (ref($info) eq 'HASH') {
                        $restart = 1 if ($info->{'Status'} eq 'EXIT');
                        
                        evTRACE and print "dispatch check_jobs <$lsf_job_id> suspended by user\n" 
                            if ($info->{'Status'} eq 'PSUSP');
                    } elsif ($info == 0) {
                        $restart = 1;
                    }
                    
                    if ($restart) {
                        my $payload = delete $heap->{dispatched}->{$lsf_job_id};
                        my $instance = $payload->{instance};

                        $kernel->post('lsftail','delete_watcher',{job_id => $lsf_job_id});

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
    return 0 if ($spool =~ /Job <$lsf_job_id> is not found/);

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

    return \%jobinfo;
}

1;
