package Workflow::Store::Db::Cache;

use strict;
use warnings;

use Workflow;
class Workflow::Store::Db::Cache {
    type_name => 'workflow cache',
    table_name => 'WORKFLOW_CACHE',
    id_by => [
        workflow_id => { is => 'INTEGER' },
    ],
    has => [
        xml         => { is => 'BLOB', is_optional => 1 },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

1;
