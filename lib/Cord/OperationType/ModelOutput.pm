
package Cord::OperationType::ModelOutput;

use strict;
use warnings;

class Cord::OperationType::ModelOutput {
    isa => 'Cord::OperationType',
    has => [
        stay_in_process => {
            value => 1
        }
    ]
};

1;
