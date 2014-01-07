package Workflow::DataSource::InstanceSchema;

use strict;
use warnings;
use Carp;
use File::lockf;
use List::MoreUtils qw(any);


class Workflow::DataSource::InstanceSchema {
    is => ['UR::DataSource::SQLite'],
};

sub table_and_column_names_are_upper_case { 0; }

our $NEXT_ID= -1;
sub _get_next_value_from_sequence {
    my($self,$sequence_name) = @_;

    return $NEXT_ID--;
}

1;
