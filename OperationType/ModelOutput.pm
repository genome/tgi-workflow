
package Workflow::OperationType::ModelOutput;

use strict;
use warnings;

class Workflow::OperationType::ModelOutput {
    isa => 'Workflow::OperationType',
    has => [
        executor => { is => 'Workflow::Executor' },
    ]
};

1;
