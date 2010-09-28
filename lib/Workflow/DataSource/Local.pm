package Workflow::DataSource::Local;

use strict;
use warnings;

use Workflow ();
use File::Temp qw(tempdir);

class Workflow::DataSource::Local {
    is => [ 'UR::DataSource::SQLite', 'UR::Singleton' ],
};

our $sqlite_db;

sub server {
    return $sqlite_db if defined $sqlite_db;

    my $self = shift;
    my $file = __FILE__;

    $file =~ s/.pm$/.sqlite3/;

    unless (-e $file && -w _) {
        my $dir = tempdir( CLEANUP => 1);
        $self->make_sqlite3_db("$file-schema",$file = "$dir/local.sqlite3");
    }
    $sqlite_db = $file;
    return $file;
}

sub make_sqlite3_db {
    my ($self, $schema_file, $file) = @_;

    system("sqlite3 $file <$schema_file");
}

1;
