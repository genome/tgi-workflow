package Workflow::Cache;

use strict;
use warnings;

use Workflow;
class Workflow::Cache {
    type_name  => 'workflow cache',
    table_name => 'WORKFLOW_PLAN',
    id_by      => [
        workflow_id => { is => 'INTEGER', column_name => 'workflow_plan_id' },
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
    schema_name => $Workflow::Config::primary_schema_name,
    data_source => $Workflow::Config::primary_data_source,
};

1;
