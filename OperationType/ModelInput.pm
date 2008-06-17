
package Workflow::OperationType::ModelInput;

use strict;
use warnings;

class Workflow::OperationType::ModelInput {
    isa => 'Workflow::OperationType',
    has => [
        executor => { is => 'Workflow::Executor', id_by => 'workflow_executor_id' },
    ]
};

1;
