package Workflow::DataSource::InstanceSchema;

use strict;
use warnings;
use Carp;
use File::lockf;
use List::MoreUtils qw(any);


class Workflow::DataSource::InstanceSchema {
    is => [ 'UR::DataSource::RDBMSRetriableOperations',
            'Workflow::DataSource::PausableRDBMS',
            'UR::DataSource::Oracle',
        ],
};

my @retriable_operations = (
    qr(ORA-25408), # can not safely replay call
    qr(ORA-03135), # connection lost contact
    qr(ORA-03113), # end-of-file on communication channel
);
sub should_retry_operation_after_error {
    my($self, $sql, $dbi_errstr) = @_;
    return any { $dbi_errstr =~ /$_/ } @retriable_operations;
}

sub table_and_column_names_are_upper_case { 1; }

sub _get_next_value_from_sequence {
my($self,$sequence_name) = @_;

    return $self->SUPER::_get_next_value_from_sequence($self->owner . '.' . $sequence_name);
}


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

1;
