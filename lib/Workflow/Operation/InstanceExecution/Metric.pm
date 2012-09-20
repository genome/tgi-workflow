package Workflow::Operation::InstanceExecution::Metric;

use strict;
use warnings;

use Workflow;
class Workflow::Operation::InstanceExecution::Metric {
    type_name  => 'workflow execution metric',
    table_name => 'EXECUTION_METRIC',
    id_by      => [
        name                  => { is => 'VARCHAR2', len => 100 },
        workflow_execution_id => { is => 'Text' },
    ],
    has => [
        value => { is => 'VARCHAR2', len => 1000, is_optional => 1 },
        instance_execution => {
            is              => 'Workflow::Operation::InstanceExecution',
            id_by           => 'workflow_execution_id',
            constraint_name => 'WEM_WIE_FK'
        },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

1;
