package Cord::Operation::InstanceExecution::Metric;

use strict;
use warnings;

use Cord;
class Cord::Operation::InstanceExecution::Metric {
    type_name  => 'cord execution metric',
    table_name => 'WORKFLOW_EXECUTION_METRIC',
    id_by      => [
        name                  => { is => 'VARCHAR2', len => 100 },
        workflow_execution_id => { is => 'NUMBER',   len => 11 },
    ],
    has => [
        value => { is => 'VARCHAR2', len => 1000, is_optional => 1 },
        instance_execution => {
            is              => 'Cord::Operation::InstanceExecution',
            id_by           => 'workflow_execution_id',
            constraint_name => 'WEM_WIE_FK'
        },
    ],
    schema_name => $Cord::Config::primary_schema_name,
    data_source => $Cord::Config::primary_data_source,
};

1;
