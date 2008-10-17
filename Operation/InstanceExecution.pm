
package Workflow::Operation::InstanceExecution;

use strict;
use warnings;

class Workflow::Operation::InstanceExecution {
    has => [
        operation_instance => { is => 'Workflow::Operation::Instance', id_by => 'instance_id' },
        status => { },
        start_time => { },
        end_time => { },
        exit_code => { },
        stdout => { },
        stderr => { },
        is_done => { is => 'Boolean' },
        is_running => { is => 'Boolean' },
        dispatch_identifier => { is => 'String' },
        debug_mode => { is => 'Boolean', default_value => 0, is_transient => 1 },
        errors => { 
            is => 'Workflow::Operation::InstanceExecution::Error', 
            is_many => 1, 
            reverse_id_by => 'execution'
        }
    ]
};

1;
