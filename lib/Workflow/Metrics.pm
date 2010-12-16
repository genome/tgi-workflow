package Workflow::Metrics;

use Workflow;
use AnyEvent;

class Workflow::Metrics {
    is  => 'Command',
};

sub new {
  my $class = shift;
  my $instance_id = shift;
  my $tempdir = shift;
  my $datadir = shift;

  my $self = {
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
  return;
}

sub run {
  return;
}

sub post_run {
  return;
}

sub report {
  my $self = shift;
  my $metrics;

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
