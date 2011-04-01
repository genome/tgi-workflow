package Workflow::Resource;

class Workflow::Resource {
    has => [
        -R 'select[ncpus >= $ && mem >= $, gtmp >= $] span[hosts=1] rusage[mem=$, gtmp=$]' -M $kb -n $cpus -q $queue
        mem_limit => { is => 'Number', doc => 'Memory limit of executing job. (MB)' },
        min_proc => { is => 'Number', doc => 'Minimum number of processors.' is_optional => 1 },
        max_proc => { is => 'Number', doc => 'Maximum number of processors.', default_value => 0 },
        time_limit => { is => 'Number', doc => 'Maximum CPU time for job.', is_optional => 1 },

        Sun Grid Engine:

        h_cpu -> per-job maximum memory limit in bytes
        s_cpu -> per-process cpu time limit in seconds
        h_data -> per-job maximum memory limit in bytes


    ]
};
