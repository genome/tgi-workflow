package Workflow::Command::Ns;

use strict;
use warnings;

use Workflow;
use Command;

class Workflow::Command::Ns {
    is => 'Command',
    doc => 'Utility commands for running serverless workflows'
};

sub sub_command_sort_position { 99 }

1;
