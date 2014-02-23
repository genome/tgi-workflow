package Workflow::DataSource::InstanceSchema;
use strict;
use warnings;
use Carp;
use File::lockf;
use List::MoreUtils qw(any);

class Workflow::DataSource::InstanceSchema {
    is => ['UR::DataSource::Pg'],
    has_constant => [
        server => { default_value => 'dbname=genome' },
        login => { default_value => 'genome' },
        auth => { default_value => 'changeme' },
        owner => { default_value => 'workflow' },
	  ],
};

1;
