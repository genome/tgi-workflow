
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
        debug_mode => { is => 'Boolean', default_value => 0, is_transient => 1 }      
    ]
};

1;
