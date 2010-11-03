package Cord::Command::Ns;

use strict;
use warnings;

use Cord;
use Command;

class Cord::Command::Ns {
    is => 'Command',
    doc => 'Utility commands for running serverless workflows'
};

sub sub_command_sort_position { 99 }

1;
