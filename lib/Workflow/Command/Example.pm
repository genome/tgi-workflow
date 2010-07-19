package Workflow::Command::Example;

use strict;
use warnings;

use Workflow;
use Command;

class Workflow::Command::Example {
    is => 'Command',
    doc => 'example commands that run workflows'
};

sub sub_command_sort_position { 99 }

1;
