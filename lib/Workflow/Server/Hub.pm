package Workflow::Server::Hub;

use strict;

use base 'Workflow::Server';
use Sys::Hostname; #exports hostname()
use Text::CSV;
use Log::Log4perl qw(:easy);
use POE qw(Component::IKC::Server
           Wheel::FollowTail);

use Workflow ();

my %JOB_STAT = (
    NULL  => 0x00,
    PEND  => 0x01,
    PSUSP => 0x02,
    RUN   => 0x04,
    SSUSP => 0x08,
    USUSP => 0x10,
    EXIT  => 0x20,
    DONE  => 0x40,
    PDONE => 0x80,
    PERR  => 0x100,
    WAIT  => 0x200,
    UNKWN => 0x10000,
);

BEGIN {
    if(defined $ENV{WF_TRACE_HUB}) {
        Log::Log4perl->easy_init($DEBUG);
    } else {
        Log::Log4perl->easy_init($ERROR);
    }
};

sub setup {
    my ($class, $announce_location_fifo) = @_;
    $Storable::forgive_me = 1;

    my $hub_port = POE::Component::IKC::Server->spawn(
        port => 0,
        name => 'Hub',
    );

    DEBUG "hub server starting on port $hub_port";
    $0 = "workflow hubd on port $hub_port";

    POE::Session->create(
        inline_states => {
            _start           => \&_lsftail_start,
            _stop            => sub { DEBUG "lsftail _stop"; },
            add_watcher      => \&_lsftail_add_watcher,
            delete_watcher   => \&_lsftail_delete_watcher,
            quit             => \&_lsftail_stop,

            handle_input     => \&_lsftail_handle_input,
            handle_reset     => sub {},
            handle_error     => \&_lsftail_handle_error,

            skip_watcher     => \&_lsftail_skip_watcher,
            skip_it          => \&_lsftail_skip_it,
            event_JOB_FINISH => \&_lsftail_event_JOB_FINISH,
        },
    );

    POE::Session->create(
        heap => {
            periodic_check_time => 300,
            job_limit           => 500,
            job_count           => 0,
            fork_limit          => 2,
            fork_count          => 0,
            dispatched          => {}, # keyed on lsf job id
            claimed             => {}, # keyed on remote kernel name
            cleaning_up         => {}, # keyed on remote kernel name
            failed              => {}, # keyed on instance id
            finalizable         => {}, # keyed on instance id
            queue               => POE::Queue::Array->new(),
            hub_port            => $hub_port,
        },
        inline_states => {
            _start        => \&_dispatch_start,
            _stop         => sub { DEBUG "dispatch _stop"; },

            periodic_check => \&_dispatch_periodic_check,
            check_jobs     => \&_dispatch_check_jobs,
            start_jobs     => \&_dispatch_start_jobs,
            fork_worker    => \&_dispatch_fork_worker,

            sig_HUP_INT_TERM => \&_dispatch_sig_HUP_INT_TERM,
            close_out        => \&_dispatch_close_out,
            unregister       => \&_dispatch_unregister,
            register         => \&_dispatch_register,

            sig_USR1  => \&_dispatch_sig_USR1,
            sig_USR2  => \&_dispatch_sig_USR2,
            sig_CHLD  => \&_dispatch_sig_CHLD,

            quit         => \&_dispatch_quit,
            quit_stage_2 => \&_dispatch_quit_stage_2,
            add_work      => \&_dispatch_add_work,
            get_work      => \&_dispatch_get_work,
            end_work      => \&_dispatch_end_work,
            finalize_work => \&_dispatch_finalize_work,
        },
    );

    POE::Session->create(
        heap => {
            # a list of info to pass to the ur process when possible
            inventory => [],

            announce_location_fifo  => $announce_location_fifo,
            hub_port                => $hub_port,
        },
        inline_states => {
            _start => \&_passthru_start,
            _stop  => sub { DEBUG "passthru _stop"; },
            announce_location => \&_passthru_announce_location,

            register_ur => \&_passthru_register_ur,
            start_ur    => \&_passthru_start_ur,
            resume_ur   => \&_passthru_resume_ur,
            pass_it_on  => \&_passthru_pass_it_on,
            relay_result => \&_passthru_relay_result,
        },
    );
}

sub _passthru_start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    DEBUG "passthru _start";
    $kernel->alias_set("passthru");

    $kernel->post('IKC', 'monitor',
            '*', {register=>'register'});

    $kernel->post('IKC', 'publish', 'passthru',
            [qw(start_ur
                resume_ur
                register_ur
                relay_result
                quit_ur)]);
    $kernel->yield('announce_location');
}

sub _passthru_announce_location {
    my $heap = $_[HEAP];

    my $hostname = hostname();
    my $hub_port = $heap->{hub_port};
    my $fifo = $heap->{announce_location_fifo};
    Workflow::Server::put_location_in_fifo($hostname, $hub_port, $fifo);
    DEBUG "passthru Announcing we are at $hostname:$hub_port to $fifo";
}

sub _passthru_register_ur {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    DEBUG "passthru Registered UR client.";
    if(scalar(@{$heap->{inventory}})) {
        $kernel->yield('pass_it_on');
    } else {
        DEBUG "passthru Not recieved message to pass through yet... waiting.";
        $kernel->delay('register_ur', 1.0);
    }
}

sub _passthru_pass_it_on {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    DEBUG "pasthru pass_it_on";
    while (my $inventory = shift @{$heap->{inventory}}) {
        $kernel->call('IKC', 'post', $inventory->{state}, $inventory->{args});
    }
}

sub _passthru_start_ur {
    my ($heap, $post_response_args) = @_[HEAP, ARG0];
    my ($args, $return_address) = @$post_response_args;
    my ($xml, $input) = @$args;

    DEBUG "passthru start ur (deferring until UR process connects)";
    push @{$heap->{inventory}}, {args => [$xml, $input, $return_address],
                                state => 'poe://UR/workflow/load_and_execute'};
}

sub _passthru_resume_ur {
    my ($heap, $post_response_args) = @_[HEAP, ARG0];
    my ($args, $return_address) = @$post_response_args;
    my ($id) = @$args;

    DEBUG "passthru resume ur $id (deferring until UR process connects)";
    push @{$heap->{inventory}}, {args => [$id, $return_address],
                                state => 'poe://UR/workflow/resume'};
}

sub _passthru_quit_ur {
    my ($kernel, $heap, $hub_kill_flag) = @_[KERNEL, HEAP, ARG0];

    DEBUG "passthr quit ur " . $hub_kill_flag ? 'and kill Hub too.' : '';
    push @{$heap->{inventory}}, {args => $hub_kill_flag,
                                state => 'poe://UR/workflow/quit'};
    $kernel->yield('pass_it_on');
}

sub _passthru_relay_result {
    my ($kernel, $arg0) = @_[KERNEL, ARG0];
    my @args = @{$arg0};
    my $return_address = shift @args;
    my $result = \@args;

    DEBUG "passthru Relaying result from ur process to " .
            $return_address->{kernel};
    $kernel->post('IKC', 'post', $return_address, $result);
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

sub _lsftail_start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    DEBUG "lsftail _start";

    $kernel->alias_set("lsftail");
    $kernel->call('IKC', 'publish', 'lsftail',
        [qw(add_watcher delete_watcher quit)]);

    # old filename may not work, try this new one as well.
    my $filename = "/usr/local/lsf/work/gsccluster1/logdir/lsb.acct";
    my $newfilename = "/usr/local/lsf/work/lsfcluster1/logdir/lsb.acct";
    if (-e $newfilename && -r _) { # same as (-e -r $newfilename)
        $filename = $newfilename;
    }

    DEBUG "lsftail Establishing Wheel on $filename";
    POE::Wheel::FollowTail->new(
        Filename   => $filename,
        InputEvent => 'handle_input',
        ResetEvent => 'handle_reset',
        ErrorEvent => 'handle_error'
    );
    # TODO remove csv and alarms, they are useless
    $heap->{csv} = Text::CSV->new({sep_char => ' '});

    $heap->{watchers} = {};
    $heap->{alarms} = {};
}

sub _lsftail_add_watcher {
    my ($heap, $kernel, $params) = @_[HEAP, KERNEL, ARG0];
    my $job_id = $params->{job_id};
    my $action = $params->{action};

    DEBUG "lsftail add_watcher $job_id";
    $heap->{watchers}{$job_id} = $action;
}

sub _lsftail_delete_watcher {
    my ($kernel, $heap, $job_id) = @_[KERNEL, HEAP, ARG0];

    DEBUG "lsftail delete_watcher $job_id";
    delete $heap->{watchers}{$job_id};
    WARN "Tried to delete non-existent lsftail watcher (job_id=$job_id)";

    my $alarm_id = delete $heap->{alarms}{$job_id};
    $kernel->alarm_remove($alarm_id) if $alarm_id;
}

sub _lsftail_skip_watcher {
    my ($kernel, $heap, $params) = @_[KERNEL, HEAP, ARG0];
    my $job_id = $params->{job_id};
    my $seconds = $params->{seconds};
    DEBUG "lsftail skip_watcher $job_id $seconds";

    if(exists $heap->{watchers}{$job_id}) {
        my $id = $kernel->delay_set('skip_it', $seconds, $job_id);
        $heap->{alarms}{$job_id} = $id;
    } else {
        WARN "Tried to skip non-existent lsftail watcher (job_id=$job_id)";
    }
}

sub _lsftail_stop {
    my ($heap) = $_[HEAP];
    DEBUG "lsftail quit";
}

sub _lsftail_handle_input {
    my ($kernel, $heap, $line) = @_[KERNEL, HEAP, ARG0];

    $heap->{csv}->parse($line);
    my @fields = $heap->{csv}->fields();

    $kernel->yield('event_' . $fields[0], $line, \@fields);
}

sub _lsftail_handle_error {
    my ($heap, $operation, $errnum, $errstr, $wheel_id) = @_[HEAP, ARG0..ARG3];

    WARN "Wheel $wheel_id: $operation error $errnum: $errstr";
}

sub _lsftail_skip_it {
    my ($kernel, $heap, $job_id) = @_[KERNEL, HEAP, ARG0];

    DEBUG "lsftail skip_it $job_id";
    if(exists($heap->{watchers}{$job_id})) {
        $heap->{watchers}{$job_id}->();
        $kernel->call($_[SESSION], 'delete_watcher', $job_id);
    } else {
        WARN "Tried to skip non-existent watcher (job_id=$job_id).";
    }
}

sub _lsftail_event_JOB_FINISH {
    my ($kernel, $heap, $line, $fields) = @_[KERNEL, HEAP, ARG0, ARG1];
    my $job_id = $fields->[3];

    if(exists $heap->{watchers}{$job_id}) {
        DEBUG "lsftail event_JOB_FINISH $job_id";
        my $offset = $fields->[22];
        $offset += $fields->[$offset+23];
        my $job_stat_code = $fields->[$offset + 24];

        my $job_status;
        while (my ($key, $value) = each(%JOB_STAT)) {
            if($job_stat_code & $value) {
                if(!defined($job_status) || $JOB_STAT{$job_status} < $value) {
                    $job_status = $key;
                }
            }
        }

        $heap->{watchers}{$job_id}->(
            $job_id, $job_status, $job_stat_code,
            @{ $fields }[$offset+28,$offset+29,$offset+54,$offset+55]
        );
        $kernel->call($_[SESSION], 'delete_watcher', $job_id);
    }
}

sub _dispatch_start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    DEBUG "dispatch _start";

    $kernel->alias_set("dispatch");
    $kernel->call('IKC', 'publish', 'dispatch',
            [qw(add_work get_work end_work quit)]);

    $kernel->post('IKC', 'monitor',
            '*', {register => 'register', unregister=>'unregister'});

    $kernel->sig('USR1', 'sig_USR1');
    $kernel->sig('USR2', 'sig_USR2');
    $kernel->sig('HUP',  'sig_HUP_INT_TERM');
    $kernel->sig('INT',  'sig_HUP_INT_TERM');
    $kernel->sig('TERM', 'sig_HUP_INT_TERM');

    $kernel->delay('periodic_check', $heap->{periodic_check_time});
}

sub _dispatch_periodic_check {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    if (scalar(keys %{$heap->{dispatched}}) > 0) {
        $kernel->yield('check_jobs');
    }

    $kernel->delay('periodic_check', $heap->{periodic_check_time});
}

sub _dispatch_check_jobs {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $number_restarted = 0;
    for my $lsf_job_id (keys %{$heap->{dispatched}}) {
        next if ($lsf_job_id =~ /^P/); # skip shortcutting jobs

        my $restart = 0;
        my $info = lsf_state($lsf_job_id);
        if(ref($info) eq 'HASH') {
            $restart = 1 if ($info->{'Status'} eq 'EXIT');

            if ($info->{'Status'} eq 'PSUSP') {
                DEBUG "dispatch check_jobs <$lsf_job_id> suspended by user";
            }
        } elsif($info == 0) {
            $restart = 1;
        }

        if($restart) {
            my $payload = delete $heap->{dispatched}->{$lsf_job_id};
            my $instance = $payload->{instance};

            $kernel->post('lsftail', 'delete_watcher', $lsf_job_id);

            DEBUG sprintf('dispatch check_jobs %s %s vanished',
                        $instance->id, $instance->name);
            $heap->{job_count}--;
            $heap->{failed}->{$instance->id}++;

            if($heap->{failed}->{$instance->id} <= 5) {
                $heap->{queue}->enqueue(150, $payload);
                $number_restarted++;
            } else {
                $kernel->yield('end_work',
                        [$lsf_job_id, undef, $instance->id, 'crashed', {}]);
            }
        }
    }
    if($number_restarted > 0) {
        # either move start_jobs to the front of the queue or put it there.
        $kernel->delay('start_jobs', 0);
    }
}

sub _construct_command {
    my ($payload, $hub_port) = @_;

    my $operation_type = $payload->{operation_type};
    my $command_class_name = $operation_type->command_class_name;
    my $namespace = (split(/::/, $command_class_name))[0];

    my $libstring = '';
    for my $lib (reverse UR::Util::used_libs()) {
        $libstring .= 'use lib "' . $lib . '"; ';
    }

    my $command = sprintf("annotate-log $^X -e '%s use %s; use %s;" .
            " use Workflow::Server::Worker;" .
            " Workflow::Server::Worker->start(\"%s\", %s)'",
            $libstring, $namespace, $command_class_name,
            hostname(), $hub_port);
    return $command;
}

sub _dispatch_start_jobs {
    my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];

    DEBUG sprintf("dispatch start_jobs %s %s",
            $heap->{job_count}, $heap->{job_limit});
    my @requeue;
    while($heap->{job_count} < $heap->{job_limit}) {
        my ($priority, $queue_id, $payload) = $heap->{queue}->dequeue_next();
        last unless defined($priority);

        my $lsf_job_id;
        if($payload->{shortcut_flag}) {
            if($heap->{fork_count} >= $heap->{fork_limit}) {
                push @requeue, $payload;
                next;
            }

            $lsf_job_id = $kernel->call($session, 'fork_worker',
                    $payload->{operation_type}->command_class_name,
                    $payload->{out_log},
                    $payload->{err_log}
            );
            $heap->{fork_count}++;
            $heap->{job_count}++;
        } else {
            my $command  = _construct_command($payload, $heap->{hub_port});
            my $resource = $payload->{operation_type}->resource;
            my $group    = $resource->group || "/workflow-worker";
            my $queue    = $resource->queue ||
                           $payload->{operation_type}->lsf_queue || 'long';
            my $name     = $payload->{instance}->name || 'worker';
            my $job = Workflow::Dispatcher::Job->create(
                command  => $command,
                resource => $resource,
                group    => $group,
                queue    => $queue,
                name     => $name,
            );

            if(defined($payload->{operation_type}->lsf_project)) {
                $job->project($payload->{operation_type}->lsf_project);
            }

            # parse the stdout & stderr paths out of bare lsf resource requests
            my $stdout = $payload->{out_log}; # defaults come from payload
            my $stderr = $payload->{err_log};
            my $lsf_resource = $payload->{operation_type}->lsf_resource;
            if ($lsf_resource =~ /-o/) {
                ($stdout) = ($lsf_resource =~ /-o ([^\s]*)/);
            }
            if ($lsf_resource =~ /-e/) {
                ($stderr) = ($lsf_resource =~ /-e ([^\s]*)/);
            }
            $job->stdout($stdout) if (defined $stdout);
            $job->stderr($stderr) if (defined $stderr);

            my $dispatcher = Workflow::Dispatcher->get();
            DEBUG sprintf("start_jobs calling command: %s",
                    $dispatcher->get_command($job));
            $lsf_job_id = $dispatcher->execute($job);

            if ($lsf_job_id) {
                $heap->{job_count}++;
                my $callback = $session->postback('finalize_work',
                        $payload->{instance}->id);

                unless($lsf_job_id =~ /^P/) { # can this even happen?
                    $kernel->post('lsftail', 'add_watcher',
                            {job_id => $lsf_job_id, action => $callback});
                }
            }
        }

        if ($lsf_job_id) {
            my ($pid) = $lsf_job_id =~ m/^P(\d+)/;
            if($pid) {
                # was a locally forked job.  Set up a sig_child handler
                $kernel->sig_child($pid, 'sig_CHLD');
            }
            $heap->{dispatched}->{$lsf_job_id} = $payload;

            $kernel->post('IKC', 'post', 'poe://UR/workflow/schedule_instance',
                    [$payload->{instance}->id, $lsf_job_id]);

            DEBUG sprintf("dispatch start_jobs submitted %s %s",
                    $lsf_job_id, $payload->{shortcut_flag});
        } else {
            DEBUG "dispatch failed to start job, will retry on next cycle";
        }
    }

    foreach my $payload (@requeue) {
        $heap->{queue}->enqueue(125, $payload);
    }
}

sub _dispatch_fork_worker {
    my ($kernel, $heap, $command_class, $stdout_file, $stderr_file) =
            @_[KERNEL, HEAP, ARG0, ARG1, ARG2];

    DEBUG "dispatch fork_worker $command_class $stdout_file $stderr_file";

    my $libstring = '';
    foreach my $lib (reverse UR::Util::used_libs()) {
        $libstring .= 'use lib "' . $lib . '"; ';
    }
    my $namespace = (split(/::/,$command_class))[0];
    my $hostname = hostname();
    my $port = $heap->{hub_port};
    my @cmd = ( 'annotate-log', $^X, '-e',
        sprintf('%s use %s; use %s; ' .
                'use Workflow::Server::Worker; ' .
                'Workflow::Server::Worker->start("%s" , %s, 2)',
        $libstring, $namespace, $command_class,
        $hostname, $port)
    );

    my $pid;
    if ($pid = fork()) {
        # parent
        DEBUG "dispatch fork_worker " . join(' ', @cmd);
        return 'P' . $pid;
    } elsif (defined $pid) {
        # child
        DEBUG "dispatch fork_worker started $$";
        open STDOUT, '>>', $stdout_file if $stdout_file;
        open STDERR, '>>', $stderr_file if $stderr_file;
        exec @cmd;
    }
}

sub _dispatch_sig_HUP_INT_TERM {
    my ($kernel) = @_[KERNEL];

    DEBUG "dispatch sig_HUP_INT_TERM";
    $kernel->call($_[SESSION],'close_out');
    $kernel->sig_handled();

    exit;
}

sub _dispatch_sig_USR1 {
    my ($kernel) = @_[KERNEL];

    DEBUG "dispatch sig_USR1";
    $kernel->yield('check_jobs');
    $kernel->sig_handled();
}

sub _dispatch_sig_USR2 {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    # either move start_jobs to the front of the queue or put it there.
    $kernel->delay('start_jobs', 0);

    my @entire_queue = $heap->{queue}->peek_items(sub { 1 });
    ERROR Data::Dumper->new([$heap, \@entire_queue],
                            ['heap', 'queue'])->Dump . "\n";

    $kernel->sig_handled();
}

sub _dispatch_sig_CHLD {
    my ($heap, $kernel, $pid, $child_error) = @_[HEAP, KERNEL, ARG1, ARG2];
    $heap->{fork_count}--;

    # either move start_jobs to the front of the queue or put it there.
    $kernel->delay('start_jobs', 0);

    if(exists($heap->{dispatched}->{'P' . $pid})) {
        $heap->{job_count}--;

        my $payload = delete $heap->{dispatched}->{'P' . $pid};
        $payload->{shortcut_flag} = 0;

        $kernel->yield('add_work', $payload);
    }

    DEBUG "dispatch sig_CHLD $pid $child_error";
}

sub _dispatch_close_out {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    DEBUG "dispatch close_out";

    ### clear queue
    DEBUG "dispatch close_out clear queue";
    $heap->{queue}->remove_items(sub { 1; });

    ### clear pending jobs
    DEBUG "dispatch close_out bkill pending";
    foreach my $id (keys %{$heap->{'dispatched'}}) {
        delete $heap->{'dispatched'}->{$id};

        DEBUG "  Killing job (id=$id)";
        system("bkill $id");
    }

    ### clear running jbos
    DEBUG "dispatch close_out bkill running";
    foreach my $remote_kernel (keys %{$heap->{claimed}}) {
        my $payload = delete $heap->{claimed}->{$remote_kernel};

        DEBUG "  Killing job (id=" . $payload->{dispatch_id} . ")";
        system('bkill ' . $payload->{dispatch_id});
    }
}

sub _dispatch_register {
    my ($remote_kernel, $real) = @_[ARG1, ARG2];

    DEBUG sprintf("dispatch register %s%s",
            $real ? '' : 'alias ', $remote_kernel);
}

# this gets called when a worker's POE kernel shuts down.
sub _dispatch_unregister {
    my ($kernel, $session, $heap, $remote_kernel, $real) =
            @_[KERNEL, SESSION, HEAP, ARG1, ARG2];

    DEBUG sprintf("dispatch unregister %s%s",
            $real ? '' : 'alias ', $remote_kernel);
    if(delete $heap->{cleaning_up}->{$remote_kernel} ||
            exists($heap->{claimed}->{$remote_kernel})) {
        $heap->{job_count}--;
        # either move start_jobs to the front of the queue or put it there.
        $kernel->delay('start_jobs', 0);
    }

    if(exists($heap->{claimed}->{$remote_kernel})) {
        my $payload = delete $heap->{claimed}->{$remote_kernel};
        my $instance = $payload->{instance};

        WARN sprintf('Blade failed on %s %s %s',
                $payload->{dispatch_id},
                $instance->id,
                $instance->name);

        my $sc = $payload->{shortcut_flag};
        if($sc) {
            $payload->{shortcut_flag} = 0;
        } else {
            $heap->{failed}->{$instance->id}++;
        }

        if($heap->{failed}->{$instance->id} <= 1) {
            $heap->{queue}->enqueue(200, $payload);
        } else {
            $kernel->yield('end_work',
                    [-666, $remote_kernel, $instance->id, 'crashed', {}]);
        }
    }
}

sub _dispatch_quit {
    my $kernel = $_[KERNEL];

    DEBUG "dispatch quit";
    $kernel->post('lsftail', 'quit');
    $kernel->yield('quit_stage_2');

    return 1; # must return something here so IKC forwards the reply
}

sub _dispatch_quit_stage_2 {
    my $kernel = $_[KERNEL];

    DEBUG "dispatch quit_stage_2";
    $kernel->alarm_remove_all();
    $kernel->alias_remove('dispatch');
    $kernel->post('IKC', 'shutdown');
}

sub _dispatch_add_work {
    my ($kernel, $heap, $params) = @_[KERNEL, HEAP, ARG0];
    my $instance = $params->{instance};

    DEBUG "dispatch add_work " . $instance->id;
    $heap->{failed}->{$instance->id} = 0;
    $heap->{queue}->enqueue(100, $params);

    # either move start_jobs to the front of the queue or put it there.
    $kernel->delay('start_jobs', 0);
}

sub _dispatch_get_work {
    my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
    my ($dispatch_id, $remote_kernel) = @$arg;

    DEBUG "dispatch get_work $dispatch_id";
    if($heap->{dispatched}->{$dispatch_id}) {
        my $payload = delete $heap->{dispatched}->{$dispatch_id};
        $payload->{dispatch_id} = $dispatch_id;
        $heap->{claimed}->{$remote_kernel} = $payload;

        my $instance       = $payload->{instance};
        my $operation_type = $payload->{operation_type};
        my $input          = $payload->{input};
        my $shortcut_flag  = $payload->{shortcut_flag};

        $kernel->post('IKC', 'post', 'poe://UR/workflow/begin_instance',
                [$instance->id, $dispatch_id]);
        $kernel->post('IKC', 'post', "poe://$remote_kernel/worker/execute",
                [$instance, $operation_type, $input, $shortcut_flag,
                $payload->{out_log}, $payload->{err_log}]);
    } else {
        WARN "dispatch get_work: unknown id $dispatch_id";
        $kernel->post('IKC','post',"poe://$remote_kernel/worker/disconnect");
    }
}

sub _dispatch_end_work {
    my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
    my ($dispatch_id, $remote_kernel, $id,
        $status, $output, $error_string, $metrics) = @$arg;

    DEBUG "dispatch end_work $dispatch_id $id";
    delete $heap->{failed}->{$id};

    my $was_shortcutting = 0;
    my $shortcut_flag;
    if($remote_kernel) {
        my $payload = delete $heap->{claimed}->{$remote_kernel};
        if($payload) {
            $shortcut_flag = $payload->{shortcut_flag};
            if ($shortcut_flag && !defined $output) {
                $was_shortcutting = 1;
                $payload->{shortcut_flag} = 0;
                $kernel->yield('add_work', $payload);
            }
        }

        $heap->{cleaning_up}->{$remote_kernel} = 1;
    }

    unless($was_shortcutting) {
        $kernel->post('IKC', 'post', 'poe://UR/workflow/end_instance',
                [$id, $status, $output, $error_string, $metrics])
    }

    $heap->{finalizable}{$id} = $dispatch_id;

    if($remote_kernel && !$shortcut_flag and $dispatch_id !~ /^P/) {
        $kernel->post('lsftail', 'skip_watcher',
                {job_id => $dispatch_id, seconds => 60});
    } elsif(!$was_shortcutting) {
        $kernel->yield('finalize_work', [$id], []);
    }
}

sub _dispatch_finalize_work {
    my ($kernel, $heap, $create_arg, $called_arg) =
            @_[KERNEL,HEAP,ARG0,ARG1];
    my ($id) = @$create_arg;
    return unless exists($heap->{finalizable}{$id});

    DEBUG "dispatch finalize_work $id";
    if(@{ $called_arg } && $called_arg->[0] eq $heap->{finalizable}{$id}) {
        my ($user_sec, $sys_sec, $mem, $swap) = @{ $called_arg }[3,4,5,6];

        $kernel->post('IKC','post','poe://UR/workflow/finalize_instance',
                [$id, ($user_sec+$sys_sec), $mem, $swap]);
    } else {
        $kernel->post('IKC','post','poe://UR/workflow/finalize_instance',
                [$id]);
    }
}


1;
