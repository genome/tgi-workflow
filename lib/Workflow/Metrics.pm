package Workflow::Metrics;

use Workflow;
use AnyEvent;

die("These metrics are unused and will be removed 5/16/2011 unless I hear otherwise: pkimmey@genome.wustl.edu");

class Workflow::Metrics {
    is  => 'Command',
};

sub new {
  my $class = shift;
  my $instance_id = shift;
  my $tempdir = shift;
  my $datadir = shift;

  my $self = {
    pid         => undef,
    instance_id => $instance_id,
    tempdir     => $tempdir,
    datadir     => $datadir,
    output      => "$datadir/output",
    errors      => "$datadir/errors",
    metrics     => "$datadir/$instance_id.metrics.txt",
  };
  bless $self, $class;
  return $self;
}

sub pre_run {
  warn "pre exec steps";
  return;
}

# FIXME: run isn't actually used, because we use an execute() method
# of a command module.  I'm not yet sure how to override such a thing.
sub run {
  return;
}

sub post_run {
  warn "post exec steps";
  return;
}

sub report {
  my $self = shift;
  my $metrics = {};

  return $metrics if (! -s $self->{metrics});

  open S, "<$self->{metrics}" or die "Unable to open metrics file: $self->{metrics}: $!";
  my @lines = <S>;
  close S;
  foreach my $line (@lines) {
    chomp $line;
    next if ($line =~ /^$/);
    my ($metric,$value) = split(': ',$line);
    $metrics->{$metric} = $value;
  }
  return $metrics;
}

1;
