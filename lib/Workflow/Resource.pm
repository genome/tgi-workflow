package Workflow::Resource;

# Note that some LSF components are defined in KB and some are in MB.
# for example, rusage[mem=100] is 100 MB but the mem limit -M 102400 is also for 100MB
#

class Workflow::Resource {
    has => [
        mem_limit => { is => 'Number', doc => 'Memory limit of executing job. (MB)', is_optional => 1 },
        tmp_space => { is => 'Number', doc => 'Temp space needed. (GB)', is_optional => 1 },
        max_tmp => { is => 'Number', doc => 'Max temp space (select) (GB)', is_optional => 1 },
        use_gtmp => { is => 'Boolean', doc => 'Use gtmp in place of tmp (genome specific)', default_value => 0 },
        min_proc => { is => 'Number', doc => 'Minimum number of processors.', is_optional => 1, default_value => 1 },
        max_proc => { is => 'Number', doc => 'Maximum number of processors.', is_optional => 1 },
        time_limit => { is => 'Number', doc => 'Maximum CPU time for job.', is_optional => 1 },
        mem_request => { is => 'Number', doc => 'Memory allocation request. (MB)', is_optional => 1 },
        queue => { is => 'String', doc => 'Job queue in which to run', is_optional => 1 }
    ]
};

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = {};

    $struct->{memLimit} = $self->mem_limit if (defined $self->mem_limit);
    $struct->{tmpSpace} = $self->tmp_space if (defined $self->tmp_space);
    $struct->{maxTmp} = $self->max_tmp if (defined $self->max_tmp);
    $struct->{useGtmp} = $self->use_gtmp if (defined $self->use_gtmp);
    $struct->{minProc} = $self->min_proc if (defined $self->min_proc);
    $struct->{maxProc} = $self->max_proc if (defined $self->max_proc);
    $struct->{timeLimit} = $self->time_limit if (defined $self->time_limit);
    $struct->{memRequest} = $self->mem_request if (defined $self->mem_request);
    $struct->{queue} = $self->queue if (defined $self->queue);

    return $struct;
}

sub create_from_xml_simple_structure {
    my ($cls, $struct) = @_;

    my $self = $cls->create();

    $self->mem_limit(delete $struct->{memLimit}) if (exists $struct->{memLimit});
    $self->tmp_space(delete $struct->{tmpSpace}) if (exists $struct->{tmpSpace});
    $self->max_tmp(delete $struct->{maxTmp}) if (exists $struct->{maxTmp});
    $self->use_gtmp(delete $struct->{useGtmp}) if (exists $struct->{useGtmp});
    $self->min_proc(delete $struct->{minProc}) if (exists $struct->{minProc});
    $self->max_proc(delete $struct->{maxProc}) if (exists $struct->{maxProc});
    $self->time_limit(delete $struct->{timeLimit}) if (exists $struct->{timeLimit});
    $self->queue(delete $struct->{queue}) if (exists $struct->{queue});

    return $self;
}
