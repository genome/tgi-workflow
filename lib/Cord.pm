package Cord;

use warnings;
use strict;

use UR;
use Cord::Time; # a copy of the old UR::Time

use Carp qw{carp};

class Cord {
    is => ['UR::Namespace'],
    type_name => 'workflow',
};

1;
