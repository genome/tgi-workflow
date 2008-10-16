
package Workflow::Operation::InstanceExecution::Error;

use strict;
use warnings;

class Workflow::Operation::InstanceExecution::Error {
    has => [
        execution => { 
            is => 'Workflow::Operation::InstanceExecution',
            id_by => 'execution_id'
        },
        error => {
            is => 'String',
            is_optional => 1
        }
    ]
};

1;
