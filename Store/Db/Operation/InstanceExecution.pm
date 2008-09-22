
package Workflow::Store::Db::Operation::InstanceExecution;

use strict;
use warnings;

use Workflow ();
use Workflow;
class Workflow::Store::Db::Operation::InstanceExecution {
    isa => 'Workflow::Operation::InstanceExecution',
    type_name => 'instance execution',
    table_name => 'INSTANCE_EXECUTION',
    id_by => [
        execution_id => { is => 'INTEGER' },
    ],
    has => [
        end_time     => { is => 'TEXT', is_optional => 1 },
        exit_code    => { is => 'INTEGER', is_optional => 1 },
        instance_id  => { is => 'INTEGER' },
        is_done      => { is => 'INTEGER', is_optional => 1 },
        is_running   => { is => 'INTEGER', is_optional => 1 },
        start_time   => { is => 'TEXT', is_optional => 1 },
        status       => { is => 'TEXT' },
        stderr       => { is => 'TEXT', is_optional => 1 },
        stdout       => { is => 'TEXT', is_optional => 1 },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

1;
