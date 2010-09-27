package Workflow::DataSource::Local;

use strict;
use warnings;

use Workflow;

class Workflow::DataSource::Local {
    is => [ 'UR::DataSource::SQLite', 'UR::Singleton' ],
};

sub server { '/gscuser/eclark/git/workflow/lib/Workflow/DataSource/Local.sqlite3' }

1;
