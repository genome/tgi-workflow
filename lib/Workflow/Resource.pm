package Workflow::Resource;

# Note that most LSF rusage is defined in KBs
#
#

class Workflow::Resource {
    has => [
        mem_limit => { is => 'Number', doc => 'Memory limit of executing job. (MB)', is_optional => 1 },
        tmp_space => { is => 'Number', doc => 'Temp space needed. (GB)', is_optional => 1 },
        use_gtmp => { is => 'Boolean', doc => 'Use gtmp in place of tmp (genome specific)', default_value => 0 },
        min_proc => { is => 'Number', doc => 'Minimum number of processors.', is_optional => 1 },
        max_proc => { is => 'Number', doc => 'Maximum number of processors.', is_optional => 1 },
        time_limit => { is => 'Number', doc => 'Maximum CPU time for job.', is_optional => 1 },
        mem_request => { is => 'Number', doc => 'Memory allocation request. (MB)', is_optional => 1 }
    ]
};
