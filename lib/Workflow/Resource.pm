package Workflow::Resource;

class Workflow::Resource {
    has => [
        mem_limit => { is => 'Number', doc => 'Memory limit of executing job. (MB)' },
        tmp_space => { is => 'Number', doc => 'Temp space needed. (GB)', default_value => 1 },
        min_proc => { is => 'Number', doc => 'Minimum number of processors.', is_optional => 1, default_value => 1 },
        max_proc => { is => 'Number', doc => 'Maximum number of processors.', is_optional => 1 },
        time_limit => { is => 'Number', doc => 'Maximum CPU time for job.', is_optional => 1 },
        mem_request => { is => 'Number', doc => 'Memory allocation request. (MB)', is_optional => 1 }
    ]
};
