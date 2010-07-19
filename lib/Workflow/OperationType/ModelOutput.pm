
package Workflow::OperationType::ModelOutput;

use strict;
use warnings;

class Workflow::OperationType::ModelOutput {
    isa => 'Workflow::OperationType',
    has => [
        stay_in_process => {
            value => 1
        }
    ]
};

1;
