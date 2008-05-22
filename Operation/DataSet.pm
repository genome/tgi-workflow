
package Workflow::Operation::DataSet;

use strict;
use warnings;

class Workflow::Operation::DataSet {
    is_transactional => 0,
    has => [
        workflow_model => { is => 'Workflow::Model', id_by => 'workflow_model_id' },
        operation_data => { is => 'Workflow::Operation::Data', is_many => 1 },
    ]
};

1;
