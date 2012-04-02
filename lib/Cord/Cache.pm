package Cord::Cache;

use strict;
use warnings;

use Cord;
class Cord::Cache {
    type_name  => 'workflow cache',
    table_name => 'WORKFLOW_PLAN',
    id_by      => [
        workflow_id => { is => 'INTEGER', column_name => 'workflow_plan_id' },
    ],
    has => [
        xml  => { is => 'BLOB', is_optional => 1 },
        plan => {
            is             => 'Cord::Operation',
            calculate_from => ['xml'],
            calculate      => q[
                Cord::Operation->create_from_xml($xml); 
            ]
        }
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Cord::DataSource::InstanceSchema',
};

1;
