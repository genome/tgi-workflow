
package Workflow::OperationType::ModelInput;

use strict;
use warnings;

class Workflow::OperationType::ModelInput {
    isa => 'Workflow::OperationType',
    has => [
        stay_in_process => {
            value => 1
        }
    ]
};

1;
