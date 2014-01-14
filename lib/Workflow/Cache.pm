package Workflow::Cache;

use strict;
use warnings;

use Workflow;
class Workflow::Cache {
    type_name  => 'workflow cache',
    table_name => 'workflow.PLAN',
	id_generator => 'workflow.workflow_id_seq',
    id_by      => [
        workflow_id => { is => 'Integer', column_name => 'workflow_plan_id' },
    ],
    has => [
        xml  => { is => 'XmlBlob', is_optional => 1 },
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
