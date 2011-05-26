package Workflow::LsfParser;

use strict;
use warnings;

use POSIX;
use Carp;

=pod

=head1 NAME

Workflow::LsfParser - Parse LSF rusage into a Workflow::Resource object

=head1 SYNOPSIS

Should be called statically e.g.:

my $resource = Workflow::LsfParser::get_resource_from_lsf_resource("-R 'select[tmp>1040]...");

=head1 DESCRIPTION

This module is a temporary measure to bridge between LSF and generic job dispatching on LSF, SGE and other job dispatchers.

=cut

class Workflow::LsfParser {
    has => [
        resource => { is => 'Workflow::Resource' },
        queue => { is => 'String' },
    ],
};

sub get_resource_from_lsf_resource {
    my $lsf_resource = shift;
    if (eval { $lsf_resource->isa("Workflow::LsfParser"); }) {
        # called as method. shift again to get our lsf rusage
        $lsf_resource = shift;
    }
    my $resource = Workflow::Resource->create();
    if (!defined $lsf_resource) {
        return $resource;
    }
    # parse mem limit -M ###kb
    my ($mem_limit) = ($lsf_resource =~ /-M\s(\d+)/);
    if (defined $mem_limit) {
        $mem_limit = ceil($mem_limit / 1024);
        $resource->mem_limit($mem_limit);
    }
    # parse cpucs -n cpus
    my $min_proc;
    ($min_proc) = ($lsf_resource =~ /-n\s(\d+)/);
    
    my ($select) = ($lsf_resource =~ /select\[([^\]]*)/);
    if (defined $select) {
        my @select_preds = ($select =~ /([a-z]+)\s*[!=><]+/g);
        foreach (@select_preds) {
            confess("Unknown select predicate: " . $_ . " on input " . $lsf_resource) unless ($_ =~ /^(model|type|maxtmp|gtmp|tmp|mem|ncpus)$/);
        }
        # handle select only predicates
        my ($max_tmp) = ($select =~ /maxtmp\s?[>=]+\s?(\d+)/);
        if (defined $max_tmp) {
            $max_tmp = ceil($max_tmp / 1024);
            $resource->max_tmp($max_tmp)
        }
        my ($ncpus) = ($select =~ /ncpus\s?[>=]+\s?(\d+)/);
        if (defined $ncpus && defined $min_proc && $min_proc != $ncpus) {
            confess("Invalid clash between select statement and -n #numcpus command flag on input " . $lsf_resource);
        }
        if (defined $ncpus && !defined $min_proc) {
            $min_proc = $ncpus;
        }
    }
    
    if (defined $min_proc) {
        $resource->min_proc($min_proc);
    }

    # handle rusage section
    my ($rusage) = ($lsf_resource =~ /rusage\[([^\]]*)/);
    if (defined $rusage) { 
        # check there isn't something we haven't seen
        my @rusage_preds = ($rusage =~ /([a-z]+)\s*[!=><]/g);

        foreach (@rusage_preds) {
            confess("Unknown rusage predicate: " . $_) unless ($_ =~ /^(model|type|gtmp|tmp|mem)$/);
        }
    
        # parse mem request rusage[mem=###mb, ...]
        my ($mem_request) = ($rusage =~ /mem=(\d+)/); 
        if (defined $mem_request) {
            $resource->mem_request($mem_request);
        }
        # parse tmp request rusage[gtmp=###gb ...]
        my ($gtmp) = ($rusage =~ /gtmp=(\d+)/);
        if (defined $gtmp) {
            $resource->tmp_space($gtmp);
            $resource->use_gtmp(1);
        }
        # if gtmp didnt do it, there should be info in
        # tmp. gtmp is genome center specific and avoids
        # a problem with lsfs tmp disk allocation sys
        my ($tmp) = ($rusage =~ /tmp=(\d+)/);
        if (defined $tmp) {
            $tmp = $tmp / 1024;
            $tmp = ceil($tmp);
            # round up, better safe than sorry
            $resource->tmp_space($tmp);
        }
    } else {
        warn("No rusage statement included in LSF pattern");
    }

    # handle queue selection
    # we could have -q foo -q bar -q baz and want "baz"
    # so this regex aims to find the LAST -q instance in the string 
    my ($queue) = $lsf_resource =~ m/.*-q\s*(\S*)/;
    if (defined $queue) {
        $resource->queue($queue);
    } else {
        warn("No LSF queue included in LSF resource pattern");
    }

    
    return $resource;
}
