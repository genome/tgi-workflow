package Cord;

use warnings;
use strict;

our $VERSION = '0.00_01';

use UR;
use Cord::Config ();

# this keeps around old parts of the UR::Object API we removed in the 0.01 release
use UR::ObjectV001removed;
use Carp qw{carp};

our @EXPORT = qw/operation operation_type operation_io/;

class Cord {
    is => ['UR::Namespace'],
    type_name => 'workflow',
};

sub operation_io {
    my ($class,$data) = @_;

    my $object;
    if (defined $data) {
        $object = Cord::OperationType::Command->create_from_command($class,$data);
    } else {
        ## i really hate doing this, but it supports old code
        $object = Cord::OperationType::Command->get($class);
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
