package Cord;

use warnings;
use strict;

our $VERSION = '0.00_01';

use UR;
use Cord::Config ();

# this keeps around old parts of the UR::Object API we removed in the 0.01 release
use UR::ObjectV001removed;
use Carp qw{carp};

class Cord {
    is => ['UR::Namespace'],
    type_name => 'workflow',
};

1;
