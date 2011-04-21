package Workflow::Dispatcher::Sge;

use strict;
use warnings;

class Workflow::Dispatcher::Sge {
    is => 'Workflow::Dispatcher',
};

sub execute {
    my $self = shift;
    my $job = shift;
    my $cmd = $self->get_command($job);
    my $sge_output = `$cmd`;
    my ($job_id) = ($sge_output = /Your job (\d+)/);
    return $job_id;
}

sub get_command {
    my $self = shift;
    my $job = shift;
    my $cmd = "qsub ";
    if (defined $job->resource->mem_free) {
        $cmd .= "-l mem_free=" . $job->resource->mem_free . "M ";
    }
    # set up resources
    return $cmd;
}
