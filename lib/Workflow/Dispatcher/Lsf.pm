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
    my $cmd = "bsub ";
    # set LSF rusage
    my $rusage = sprintf("-R 'select[ncpus >= %s && mem >= %s && gtmp >= %s] span[hosts=1] rusage[mem=%s, gtmp=%s]' ", 
        $job->resource->min_proc,
        $job->resource->mem_limit,
        $job->resource->tmp_space,
        $job->resource->mem_limit,
        $job->resource->tmp_space
        );
    $cmd .= $rusage;
    # add memory & number of cores requirements
    if (defined $job->resource->mem_limit) {
        $cmd .= sprintf("-M %s ", $job->resource->mem_limit * 1024);
    }
    if (defined $job->resource->min_proc) {
        $cmd .= sprintf("-n %s ", $job->resource->min_proc);
    }
    # set queue
    if (defined $job->queue) {
        $cmd .= sprintf("-q %s ", $job->queue);
    }
    elsif (defined $self->default_queue) {
        $cmd .= sprintf("-q %s ", $job->default_queue);
    }
    $cmd .= $job->command;
    return $cmd;
}
