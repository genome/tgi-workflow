package Workflow::Server::Worker;

use strict;

use AnyEvent::Impl::POE;
use AnyEvent::Util;
use AnyEvent;

use File::Basename;
use File::Temp;

use POE;
use POE::Component::IKC::Client;
use POE::Component::IKC::Responder;
use Error qw(:try);

use Workflow ();

our $job_id;

sub start {
    my ($class, $host, $port, $use_pid) = @_;

    $host ||= 'localhost';
    $port ||= die 'no port number';

    if($use_pid) {
        if($use_pid == 2) {
            # means use my parent's pid
            # if this code is ever run in a thread, the next line
            # breaks on linux.
            $job_id = 'P' . getppid();
        } else {
            $job_id = 'P' . $use_pid;
        }
    } elsif(exists $ENV{LSB_JOBID}) {
        $job_id = $ENV{LSB_JOBID};
    } elsif(exists $ENV{'WF_FORK_JOBID'}) {
        $job_id = $ENV{'WF_FORK_JOBID'};
    }
    create_ikc_responder();

    create_ikc_responder();
    POE::Component::IKC::Client->spawn(
        ip=>$host,
        port=>$port,
        name=>'Worker',
        on_connect=>\&_build,
    );

    $Storable::forgive_me = 1;
    POE::Kernel->run();
}

sub _build {
    POE::Session->create(
        inline_states => {
            _start     => \&_worker_start,
            execute    => \&_worker_execute,
            disconnect => \&_worker_disconnect,
            get_work   => \&_worker_get_work,
        }
    );
}

sub _worker_start {
    my ($kernel) = @_[KERNEL];
    $kernel->alias_set("worker");
    $kernel->call('IKC','publish','worker',[qw(execute disconnect)]);

    $kernel->yield('get_work');
}


sub _worker_execute {
    my ($kernel, $arg) = @_[KERNEL, ARG0];
    my ($instance, $type, $input, $sc_flag, $out_log, $err_log) = @$arg;

    $kernel->alarm_remove_all();

    $ENV{'WORKFLOW_PARENT_EXECUTION'} = $instance->{current_execution_id};

    my $profiler = $ENV{'WF_PROFILER'};
    if($profiler && ! -e $err_log) {
        # Require an err_log for profiling because this is the target destination
        # of our metrics output file.
        warn "WF_PROFILER is set but err_log is undefined, disabling profiling";
        delete $ENV{'WF_PROFILER'};
        $profiler = undef;
    } elsif($profiler && -e $err_log) {
        # See if we're running under LSF and LSF gave us a directory that will be
        # auto-cleaned up when the job terminates.  If so, use it for temp space.
        my $tmp_location = $ENV{'TMPDIR'} || "/tmp";
        if($ENV{'LSB_JOBID'}) {
            my $lsf_possible_tempdir = "$ENV{TMPDIR}/$ENV{LSB_JOBID}.tmpdir";
            $tmp_location = $lsf_possible_tempdir if -d $lsf_possible_tempdir;
        }
        my $tempdir = File::Temp::tempdir("workflow-metrics-XXXXX", 
                DIR=>$tmp_location, CLEANUP => 1);

        # Determine output path from err_log
        my $outdir = File::Basename::dirname($err_log);

        my $package = 'Workflow::Metrics::' . ucfirst(lc($profiler));
        eval "use $package";
        if($@) {
            warn "WF_PROFILER is set to '$package' but failed " .
                 "to 'use $package': disabling profiling: $!";
            delete $ENV{'WF_PROFILER'};
            $profiler = undef;
        } else {
            $profiler = $package->new($instance->{current_execution_id},
                    $tempdir, $outdir);
        }
    }

    $profiler->pre_run() if $profiler;

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
    if($@ || !defined($output) ) {
        print STDERR "Command module died or returned undef.\n" unless $sc_flag;
        if($@) {
            print STDERR $@;
            $error_string = "$@";
        } else {
            $error_string = "Command module returned undef";
        }
        $status = 'crashed';
    } else {
        my $result = UR::Context->commit();
        unless($result) {
            $error_string = 'Commit failed.';
            $status = 'crashed';
        }
    }

    ## metrics should only contain plain key value pairs
    #  it is relayed over the wire before it goes in oracle
    #  so dont try to shove a bam in it
    my %metrics;

    if($profiler) {
      $profiler->post_run();
      %metrics = %{ $profiler->report() };
    }

    $kernel->post('IKC','post','poe://Hub/dispatch/end_work',
            [$job_id, $kernel->ID, $instance->id, $status,
             $output, $error_string, \%metrics]);
    $kernel->yield('disconnect');
}

sub _worker_disconnect {
    $_[KERNEL]->post('IKC','shutdown');
}

sub _worker_get_work {
    my ($kernel) = @_[KERNEL];

    my $kernel_name = $kernel->ID;
    $kernel->post('IKC','post','poe://Hub/dispatch/get_work',
                [$job_id, $kernel_name]);
}

1;
