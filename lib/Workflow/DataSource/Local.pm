package Workflow::DataSource::Local;

use strict;
use warnings;

use Workflow;

class Workflow::DataSource::Local {
    is => [ 'UR::DataSource::SQLite', 'UR::Singleton' ],
};

sub server { 
    my $file = __FILE__;
    $file =~ s/.pm$/.sqlite3/;
    return $file;
}

1;
