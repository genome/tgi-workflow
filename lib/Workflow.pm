package Workflow;
use warnings;
use strict;
use UR;
use Workflow::Env;
use Workflow::Time; # a copy of the old UR::Time
use Carp qw{carp};

class Workflow {
    is => ['UR::Namespace'],
    type_name => 'workflow',
};

1;
