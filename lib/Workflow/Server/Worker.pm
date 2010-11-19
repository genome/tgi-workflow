
package Workflow::Server::Worker;

use strict;

use AnyEvent::Impl::POE;
use AnyEvent::Util;
use AnyEvent;
use POE;

use File::Copy;
use File::Basename;
use File::Temp;
use File::Path;

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
        if ($use_pid == 2) {
            # means use my parent's pid
            # if this code is ever run in a thread, the next line
            # breaks on linux.
            $job_id = 'P' . getppid();
        } else {
            $job_id = 'P' . $$;
        }
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
                my ($instance, $type, $input, $sc_flag, $out_log, $err_log) = @$arg;

                $kernel->alarm_remove_all;

                $ENV{'WORKFLOW_PARENT_EXECUTION'} = $instance->{current_execution_id};

                # See if we're running under LSF and LSF gave us a directory that will be
                # auto-cleaned up when the job terminates
                my $tmp_location = $ENV{'TMPDIR'} || "/tmp";
                if ($ENV{'LSB_JOBID'}) {
                    my $lsf_possible_tempdir = sprintf("%s/%s.tmpdir", $ENV{'TMPDIR'}, $ENV{'LSB_JOBID'});
                    $tmp_location = $lsf_possible_tempdir if (-d $lsf_possible_tempdir);
                }
                # tempdir() thows its own exception if there's a problem
                my $tempdir = File::Temp::tempdir("workflow-metrics-XXXXX", DIR=>$tmp_location, CLEANUP => 1);
                File::Path::make_path($tempdir);

                my $collectl_cv;
                my $collectl_pid;
                my $collectl_cmd = "/usr/bin/collectl";
                my $collectl_args = "--all --export lexpr -f $tempdir -on";
                my $collectl_output;
                if ($ENV{'WF_PROFILER'} && -e $err_log) {
                    # Both WF_PROFILER and error logging must be set in order to be
                    # sure that we have a path to put our profiling stats in.
                    $collectl_output = $err_log;
                    $collectl_output =~ s/.err/.collectl.out/;
                    if (! -x $collectl_cmd) {
                        warn "WF_PROFILER is enabled, but $collectl_cmd is not present and executable\n";
                    } else {
                      # Note that we undefine PERL5LIB because collectl is perl
                      # and we want it to use the proper perl.
                      $collectl_cv = AnyEvent::Util::run_cmd(
                          "$collectl_cmd $collectl_args",
                          close_all => 1,
                          '$$' => \$collectl_pid,
                          on_prepare => sub { delete $ENV{PERL5LIB} }
                          );

                      my $cv = AnyEvent->condvar;
                      # We use a timer to give collectl time to start up.
                      my $w = AnyEvent->timer(
                          after => 2,
                          cb => $cv
                          );
                      $cv->recv;
                    }
                }

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
                    print STDERR "Command module died or returned undef.\n" unless ($sc_flag);
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

                if ($collectl_cv) {
                    ## shut down collectl
                    kill 15, $collectl_pid;
                    $collectl_cv->recv;
                    move "$tempdir/L", $collectl_output or die "Failed to move collectl output file $tempdir/L to $collectl_output: $!";
                }

                ## this should only contain plain key value pairs
                #  it is relayed over the wire before it goes in oracle
                #  so dont try to shove a bam in it
                my %metrics;

                # parse collectl output if present and store metrics.
                if (-s $collectl_output) {
                    open S, "<$collectl_output" or die "Unable to open collectl output file: $collectl_output: $!";
                    my @lines = <S>;
                    close S;
                    foreach my $line (@lines) {
                        chomp $line;
                        my ($metric,$value) = split(' ',$line);
                        $metrics{$metric} = $value;
                    }
                }

                $kernel->post('IKC','post','poe://Hub/dispatch/end_work',[$job_id, $kernel->ID, $instance->id, $status, $output, $error_string, \%metrics]);
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
