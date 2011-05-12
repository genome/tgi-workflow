package Workflow::Resource;

# Note that some LSF components are defined in KB and some are in MB.
# for example, rusage[mem=100] is 100 MB but the mem limit -M 102400 is also for 100MB
#

class Workflow::Resource {
    has => [
        mem_limit => { is => 'Number', doc => 'Memory limit of executing job. (MB)', is_optional => 1 },
        tmp_space => { is => 'Number', doc => 'Temp space needed. (GB)', is_optional => 1 },
        use_gtmp => { is => 'Boolean', doc => 'Use gtmp in place of tmp (genome specific)', default_value => 0 },
        min_proc => { is => 'Number', doc => 'Minimum number of processors.', is_optional => 1, default_value => 1 },
        max_proc => { is => 'Number', doc => 'Maximum number of processors.', is_optional => 1 },
        time_limit => { is => 'Number', doc => 'Maximum CPU time for job.', is_optional => 1 },
        mem_request => { is => 'Number', doc => 'Memory allocation request. (MB)', is_optional => 1 }
    ]
};
