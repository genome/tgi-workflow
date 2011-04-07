package Workflow::Dispatcher::Lsf;

use strict;
use warnings;

class Workflow::Dispatcher::Lsf {
    is => 'Workflow::Dispatcher',
};

sub execute {
    my $self = shift;
    my $job = shift;
    my $cmd = $self->get_command($job);
    my $bsub_output = `$cmd`;
    my ($job_id, $queue) = ($bsub_output =~ /^Job <([^>]+)> is submitted to\s[^<]*queue <([^>]+)>\..*/);
    return $job_id;
}

sub get_command {
    my $self = shift;
    my $job = shift;
    my $cmd = "bsub " . $job->command;
    return $cmd;
}
