package Workflow::LsfParser;

use strict;
use warnings;

use POSIX;

class Workflow::LsfParser {
    has => [
        resource => { is => 'Workflow::Resource' },
        queue => { is => 'String' },
    ],
};

sub get_resource_from_lsf_resource {
    my $lsf_resource = shift;
    my $resource = Workflow::Resource->create();
    # parse mem limit -M ###kb
    my ($mem_limit) = ($lsf_resource =~ /-M\s(\d+)/);
    if (defined $mem_limit) {
        $mem_limit = ceil($mem_limit / 1024);
        $resource->mem_limit($mem_limit);
    }
    # parse cpucs -n cpus
    my ($min_proc) = ($lsf_resource =~ /-n\s(\d+)/);
    if (defined $min_proc) {
        $resource->min_proc($min_proc);
    }
    
    my ($select) = ($lsf_resource =~ /select\[([^\]]*)/);
    if (defined $select) {
        my @select_preds = ($select =~ /([a-z]+)\s*[=><]/g);
        foreach (@select_preds) {
            die("Unknown select predicate: " . $_) unless ($_ =~ /type|gtmp|tmp|mem/);
        }
    } else {
        die("No select statement included in LSF pattern");
    }


    # handle rusage section
    my ($rusage) = ($lsf_resource =~ /rusage\[([^\]]*)/);
    
    # check there isn't something we haven't seen
    my @rusage_preds = ($rusage =~ /([a-z]+)\s*[=><]/g);

    foreach (@rusage_preds) {
        die("Unknown rusage predicate: " . $_) unless ($_ =~ /type|gtmp|tmp|mem/);
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
    return $resource;
}
