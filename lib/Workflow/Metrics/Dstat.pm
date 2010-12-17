package Workflow::Metrics::Dstat;

use base qw/Workflow::Metrics/;

use strict;
use warnings;

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
    my $cmd = "/usr/bin/dstat";
    if (! -x $cmd) {
        warn "comand not found: $cmd: NOT profiling";
        return;
    }

    my $args = "-Tcldigmnpsy --ipc --lock --tcp --udp --unix --net-packets --nfs3 --output $self->{metrics}";
    if ($ENV{WF_PROFILER_ARGS}) {
        warn "WF_PROFILER_ARGS overrides default profiler args";
        $args = $ENV{WF_PROFILER_ARGS};
    }

    $self->{cv} = AnyEvent::Util::run_cmd(
        "$cmd $args",
        '>' => "/dev/null",
        '2>' => "/dev/null",
        close_all => 1,
        '$$' => \( $self->{pid} ),
        allow_failed_exit_code => 1,
    );
    $self->_sleep(2);
}

sub run {
  my $self = shift;
  my $cmd = shift;
  my $args = shift;

  my $cmd_cv = AnyEvent::Util::run_cmd(
    '>' => $self->{output},
    '2>' => $self->{errors},
    cmd => "$cmd $args"
  );

  $cmd_cv->recv;
}

sub post_run {
  my $self = shift;
  return if (! defined $self->{pid});

  # Now that cmd_cv->cmd status is true, we're back, and we send SIGTERM to cmd pid.
  kill 15, $self->{pid};
  # Now recv on that condition variable, which will catch the signal and exit.
  # We wrap in eval and examine $@ to ensure we catch the signal we sent, but we can still
  # observe any unexpected events.
  eval {
    $self->{cv}->recv;
  };
  if (defined $@ && $@ !~ /^COMMAND KILLED\. Signal 15/) {
    # unexpected death message from shellcmd.
    die $@;
  }
}

sub report {
  my $self = shift;
  my $metrics = {};
  # dstat output is not key/value
  return $metrics if (! -s $self->{metrics});

  #open S, "<$self->{metrics}" or die "Unable to open metrics file: $self->{metrics}: $!";
  #my @lines = <S>;
  #close S;
  #foreach my $line (@lines) {
  #  chomp $line;
  #  next if ($line =~ /^$/);
  #  my ($metric,$value) = split(' ',$line);
  #  $metrics->{$metric} = $value;
  #}
  #return $metrics;
}

1;
