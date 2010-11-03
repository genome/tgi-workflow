package Cord::Command::Example;

use strict;
use warnings;

use Cord;
use Command;

class Cord::Command::Example {
    is => 'Command',
    doc => 'example commands that run workflows'
};

sub sub_command_sort_position { 99 }

1;
