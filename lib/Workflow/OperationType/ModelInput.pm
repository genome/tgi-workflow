
package Cord::OperationType::ModelInput;

use strict;
use warnings;

class Cord::OperationType::ModelInput {
    isa => 'Cord::OperationType',
    has => [
        stay_in_process => {
            value => 1
        }
    ]
};

1;
