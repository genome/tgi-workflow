package Workflow::Dispatcher::Lsf;

use strict;
use warnings;

class Workflow::Dispatcher::Lsf {
    is => 'Workflow::Dispatcher',
};

# The OpenLava implementation of LSF has reduced features
our $OPENLAVA = ((`which bsub` =~ /openlava/) ? 1 : 0);

sub execute {
    my $self = shift;
    my $job = shift;
    my $cmd = $self->get_command($job);
    warn("Workflow LSF Dispatcher issuing command: $cmd");

    my $bsub_output = `$cmd`;

    my ($job_id, $queue) = ($bsub_output =~ /^Job <([^>]+)> is submitted to\s[^<]*queue <([^>]+)>\..*/);
    return $job_id;
}

sub get_command {
    my $self = shift;
    my $job = shift;
    my $cmd = "bsub ";

    # set LSF rusage

    #For testing on small resource machines, reduce memory and core requirements by some factor (or to some max)
    #For OPENLAVA (standalone) situations only
    if ($OPENLAVA && $ENV{'WF_LOW_RESOURCES'}){
      if($job->resource->min_proc>4){
        $job->resource->min_proc(4);
      }
      if($ENV{'WF_LOW_MEMORY'}) { #ENV for memory request usage. specified in MB.
        if($job->resource->mem_request>$ENV{'WF_LOW_MEMORY'}){
          $job->resource->mem_request($ENV{'WF_LOW_MEMORY'});
        }
      }
      elsif($job->resource->mem_request>1000){
          $job->resource->mem_request(1000);
      }
    }

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
            push (@selects, sprintf("gtmp>=%s", $job->resource->tmp_space)) unless $OPENLAVA;
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
            push(@rusages, sprintf("gtmp=%s", $job->resource->tmp_space)) unless $OPENLAVA;
        } else {
            push(@rusages, sprintf("tmp=%s", $job->resource->tmp_space*1024));
        }
    }

    if (defined $job->resource->upload_bandwidth) {
        push @rusages, sprintf("internet_upload_mbps=%s", $job->resource->upload_bandwidth);
    }
    if (defined $job->resource->download_bandwidth) {
        push @rusages, sprintf("internet_download_mbps=%s", $job->resource->download_bandwidth);
    }

    my $rusage;
    #OPENLAVA uses colon as a delimiter for rusage.
    if ($OPENLAVA) {
      $rusage = join(":", @rusages);
    }
    else {
      $rusage = join(", ", @rusages);
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
        unless ($OPENLAVA) {
            $cmd .= sprintf("-n %s ", $job->resource->min_proc);
        }
    }

    # set queue
    if (my $queue = $ENV{'WF_LSF_QUEUE'}) {
        $cmd .= sprintf("-q %s ", $queue);
    }
    elsif (defined $job->queue) {
        $cmd .= sprintf("-q %s ", $job->queue);
    }
    elsif (defined $self->default_queue) {
        $cmd .= sprintf("-q %s ", $job->default_queue);
    }
    
    $cmd .= sprintf("-o %s ", $job->stdout) if (defined $job->stdout); 
    $cmd .= sprintf("-e %s ", $job->stderr) if (defined $job->stderr);
    
    $cmd .= sprintf("-g %s ", $job->group) if !$ENV{WF_EXCLUDE_JOB_GROUP} and (defined $job->group);
    
    if (defined $job->name) {
        if ($job->name =~ /\s/) {
            $cmd .= sprintf('-J "%s" ', $job->name);
        } else {
            $cmd .= sprintf('-J %s ', $job->name);
        }
    }
    if ( my $project = $ENV{'WF_LSF_PROJECT'} or $job->project() ) {
        $cmd .= sprintf('-P "%s" ', $project);
    }

    # Workflow exclusive execution mode to run only one job per blade -- for use when benchmarking
    if ($ENV{'WF_LSF_EXCLUSIVE'}) {
        $cmd .= "-x ";
    }

    if ($ENV{"WF_JOB_EXTRA_PARAMS"}) {
        $cmd .= ' ' . $ENV{"WF_JOB_EXTRA_PARAMS"} . ' ';
    }

    $cmd .= $job->command;
    my $cmd_to_debug = $ENV{'WF_DEBUG_MATCH'};
    if ($cmd_to_debug and ($cmd =~ /$cmd_to_debug/)) {
        my $perl_name = $^X;
        if ($cmd =~ s|$perl_name|$perl_name -d:ptkdb|){
            print "Running command with ptkdb debugger: $cmd\n";
        }
    }
    return $cmd;
}

1;
