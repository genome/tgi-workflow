package Workflow::Cache;

use strict;
use warnings;

use Workflow;
class Workflow::Cache {
    type_name  => 'workflow cache',
    table_name => 'PLAN',
	id_generator => '-uuid',
    id_by      => [
        workflow_id => { is => 'Text', column_name => 'workflow_plan_id' },
    ],
    has => [
        xml  => { is => 'BLOB', is_optional => 1 },
        plan => {
            is             => 'Workflow::Operation',
            calculate_from => ['xml'],
            calculate      => q[
                Workflow::Operation->create_from_xml($xml); 
            ]
        }
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

1;
