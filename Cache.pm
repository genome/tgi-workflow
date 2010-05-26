package Workflow::Cache;

use strict;
use warnings;

use Workflow;
class Workflow::Cache {
    type_name => 'workflow cache',
    table_name => 'WORKFLOW_PLAN',
    id_by => [
        workflow_id => { is => 'INTEGER', column_name => 'workflow_plan_id' },
    ],
    has => [
        xml         => { is => 'BLOB', is_optional => 1 },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

1;
