package Workflow::DataSource::InstanceSchema;
use strict;
use warnings;
use Carp;

class Workflow::DataSource::InstanceSchema {
    is => ['UR::DataSource::Pg'],
    has_constant => [
        server => { default_value => 'dbname=genome;host=gms-postgres' },
        login => { default_value => 'genome' },
        auth => { default_value => 'TGIlab' },
        owner => { default_value => 'workflow' },
	  ],
};

1;

