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
    my @selects;
    
    push (@selects, sprintf("ncpus>=%s", $job->resource->min_proc));

    if (defined $job->resource->mem_request) {
        push (@selects, sprintf("mem>=%s", $job->resource->mem_request));
    }

    if (defined $job->resource->max_tmp) {
        push (@selects, sprintf("maxtmp>=%s", $job->resource->max_tmp * 1024));
    }

    if (defined $job->resource->tmp_space) {
        if ($job->resource->use_gtmp) {
            push (@selects, sprintf("gtmp>=%s", $job->resource->tmp_space));
        } else {
            push (@selects, sprintf("tmp>=%s", $job->resource->tmp_space * 1024));
        }
    }
    my $select = join(" && ", @selects);
    $cmd .= sprintf("-R 'select[%s] span[hosts=1]", $select);

    my @rusages;

    if (defined $job->resource->mem_request) {
        push (@rusages, sprintf("mem=%s", $job->resource->mem_request));
    }

    if (defined $job->resource->tmp_space) {
        if ($job->resource->use_gtmp) {
            push(@rusages, sprintf("gtmp=%s", $job->resource->tmp_space));
        } else {
            push(@rusages, sprintf("tmp=%s", $job->resource->tmp_space*1024));
        }
    }
    
    my $rusage = join(", ", @rusages);
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
    
    $cmd .= sprintf("-g %s ", $job->group) if (defined $job->group);
    
    if (defined $job->name) {
        if ($job->name =~ /\s/) {
            $cmd .= sprintf('-J "%s" ', $job->name);
        } else {
            $cmd .= sprintf('-J %s ', $job->name);
        }
    }
    if (defined $job->project) {
        if ($job->project =~ /\s/) {
            $cmd .= sprintf('-P "%s" ', $job->project);
        } else {
            $cmd .= sprintf('-P %s ', $job->project);
        }
    }

    $cmd .= $job->command;
    return $cmd;
}
