use strict;
use warnings;

package Workflow::DataSource::InstanceSchema;

use Workflow;

class Workflow::DataSource::InstanceSchema {
    is => ['UR::DataSource::SQLite'],
    type_name => 'workflow datasource instanceschema',
};



1;
