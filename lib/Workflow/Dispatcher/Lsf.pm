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
    
    # select string consists of a series of args
    # of RESOURCE >= NUMBER && together
    my $select = "";

    my $num_selects = 1;

    $num_selects++ if (defined $job->resource->mem_request);
    $num_selects++ if (defined $job->resource->tmp_space);

    $select .= sprintf("ncpus>=%s", $job->resource->min_proc);
    $num_selects--;
    $select .= " && " if ($num_selects > 0);

    if (defined $job->resource->mem_request) {
        $select .= sprintf("mem>=%s", $job->resource->mem_request);
        $num_selects--;
    }
    $select .= " && " if ($num_selects > 0);

    if (defined $job->resource->tmp_space) {
        if ($job->resource->use_gtmp) {
            $select .= sprintf("gtmp>=%s", $job->resource->tmp_space);
        } else {
            $select .= sprintf("tmp>=%s", $job->resource->tmp_space * 1024);
        }
    }

    $cmd .= sprintf("-R 'select[%s] span[hosts=1]", $select);

    my $num_rusages = 0;
    my $rusage = "";

    $num_rusages++ if (defined $job->resource->mem_request);
    $num_rusages++ if (defined $job->resource->tmp_space);

    # if there is going to be

    if (defined $job->resource->mem_request) {
        $rusage .= sprintf("mem=%s", $job->resource->mem_request);
        $num_rusages--;
    }
    $rusage .= ", " if ($num_rusages > 0);

    if (defined $job->resource->tmp_space) {
        if ($job->resource->use_gtmp) {
            $rusage .= sprintf("gtmp=%s", $job->resource->tmp_space);
        } else {
            $rusage .= sprintf("tmp=%s", $job->resource->tmp_space*1024);
        }
    }

    if ($rusage ne "") {
        $cmd .= sprintf(" rusage[%s]' ", $rusage);
    } else {
        $cmd .= "' ";
    }



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
    
    $cmd .= sprintf("-o %s ", $job->stdout) if (defined $job->stdout); 
    $cmd .= sprintf("-e %s ", $job->stderr) if (defined $job->stderr);
    $cmd .= $job->command;
    return $cmd;
}
