
package Workflow::Store::Db::Operation::InstanceExecution;

use strict;
use warnings;

use Workflow ();
use Workflow;
class Workflow::Store::Db::Operation::InstanceExecution {
    is         => ['Workflow::Operation::InstanceExecution'],
    type_name  => 'instance execution',
    table_name => 'WORKFLOW_INSTANCE_EXECUTION',
    id_by      => [
        execution_id =>
          { is => 'NUMBER', len => 11, column_name => 'WORKFLOW_EXECUTION_ID' },
    ],
    has => [
        end_time  => { is => 'TIMESTAMP', len => 20, is_optional => 1 },
        exit_code => { is => 'NUMBER',    len => 5,  is_optional => 1 },
        instance_id =>
          { is => 'NUMBER', len => 11, column_name => 'WORKFLOW_INSTANCE_ID' },
        is_done       => { is => 'NUMBER',    len => 2,   is_optional => 1 },
        is_running    => { is => 'NUMBER',    len => 2,   is_optional => 1 },
        start_time    => { is => 'TIMESTAMP', len => 20,  is_optional => 1 },
        status        => { is => 'VARCHAR2',  len => 15 },
        stderr        => { is => 'VARCHAR2',  len => 255, is_optional => 1 },
        stdout        => { is => 'VARCHAR2',  len => 255, is_optional => 1 },
        cpu_time      => { is => 'NUMBER',    len => 13,  is_optional => 1 },
        max_threads   => { is => 'NUMBER',    len => 4,   is_optional => 1 },
        max_swap      => { is => 'NUMBER',    len => 10,  is_optional => 1 },
        max_processes => { is => 'NUMBER',    len => 4,   is_optional => 1 },
        max_memory    => { is => 'NUMBER',    len => 10,  is_optional => 1 },
        dispatch_identifier => {
            is          => 'VARCHAR2',
            len         => 10,
            column_name => 'DISPATCH_ID',
            is_optional => 1
        },
        user_name     => { is => 'VARCHAR2',  len => 20,  is_optional => 1 },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

1;
