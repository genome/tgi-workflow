package Workflow::Metrics::Dstat;

use base qw/Workflow::Metrics/;

use strict;
use warnings;
use Sys::Hostname;

sub _sleep {
  # Use an event timer to sleep within the event loop
  my $self = shift;
  my $seconds = shift;
  my $sleep_cv = AnyEvent->condvar;
  my $w = AnyEvent->timer(
      after => $seconds,
      cb => $sleep_cv
  );
  $sleep_cv->recv;
}

sub pre_run {
    my $self = shift;
    # Ideally we'd use locally installed dstat.  But we're not there yet.
    #my $cmd = "/usr/bin/dstat";
    # We want the option to write stats to graphite over the network.
    # This requires dstat >= 0.7.0-3.
    my $cmd = "/gsc/var/gsc/systems/blades/dstat-0.7.0-3";
    if (! -x $cmd) {
        warn "comand not found: $cmd: NOT profiling";
        return;
    }

    #my $args = "-Tcldigmnpsy --ipc --lock --tcp --udp --unix --net-packets --nfs3 --output $self->{metrics}";
    my $args = "-Tcldigmnpsy --ipc --lock --tcp --udp --unix --output " . $self->{metrics};
    if ($ENV{WF_PROFILER_ARGS}) {
        warn "WF_PROFILER_ARGS overrides default profiler args";
        $args = $ENV{WF_PROFILER_ARGS};
    }

    warn "profiling on " . hostname . ": $cmd $args";

    $self->{cv} = AnyEvent::Util::run_cmd(
        "$cmd $args",
        '>' => "/dev/null",
        '2>' => "/dev/null",
        close_all => 1,
        '$$' => \( $self->{pid} ),
        allow_failed_exit_code => 1,
    );

    $self->_sleep(2);

    warn "started pid: " . $self->{pid};
}

sub post_run {
  my $self = shift;

  # Check if our process is running...
  unless (kill 0, $self->{pid}) {
    warn "profiler pid " . $self->{pid} . " on " . hostname . " is no longer running";
    return;
  }

  warn "kill profiler pid " . $self->{pid} . " on " . hostname;

  # Now that cmd_cv->cmd status is true, we're back, and we send SIGTERM to cmd pid.
  kill 15, $self->{pid};
  # Now recv on that condition variable, which will catch the signal and exit.
  # We wrap in eval and examine $@ to ensure we catch the signal we sent, but we can still
  # observe any unexpected events.
  eval {
    $self->{cv}->recv;
  };
  if ($@ && $@ !~ /^COMMAND KILLED\. Signal 15/) {
    # unexpected death message from shellcmd.
    # Don't die here, we don't want shutting down the profiler to interrupt
    # the job being profiled.  Just warn.
    warn "unexpected death of profiler: $@";
  }
}

sub report {
  # dstat output is not key/value
  my $self = shift;
  return {};
}

1;
