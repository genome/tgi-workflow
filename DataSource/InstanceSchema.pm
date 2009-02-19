use strict;
use warnings;

package Workflow::DataSource::InstanceSchema;

use Workflow;

class Workflow::DataSource::InstanceSchema {
    is => ['UR::DataSource::Oracle'],
    type_name => 'workflow datasource instanceschema',
};

sub server {
    "gscprod";
}

sub login {
    "wrkflo_user";
}

sub auth {
    "wfl0us3r";
}

sub owner {
    "WORKFLOW";
}

sub _get_next_value_from_sequence {
my($self,$sequence_name) = @_;

    return $self->SUPER::_get_next_value_from_sequence($self->owner . '.' . $sequence_name);
}


1;
