package Workflow;

use warnings;
use strict;

use UR;

# this keeps around old parts of the UR::Object API we removed in the 0.01 release
use UR::ObjectV001removed;
use Carp qw{carp};

our @EXPORT = qw/operation operation_type operation_io/;

class Workflow {
    is => ['UR::Namespace'],
    type_name => 'workflow',
};

sub operation_io {
    my ($class,$data) = @_;

    my $object;
    if (defined $data) {
        $object = Workflow::OperationType::Command->create_from_command($class,$data);
    } else {
        ## i really hate doing this, but it supports old code
        $object = Workflow::OperationType::Command->get($class);
    }

    return $object;
}

## synonyms that should be removed

sub operation {
    operation_io(@_);
}

sub operation_type {
    operation_io(@_);
}

1;
