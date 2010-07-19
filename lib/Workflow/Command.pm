
package Workflow::Command;

use strict;
use warnings;
use Workflow;

class Workflow::Command {
    is => ['Command'],
    english_name => 'workflow command',
};

sub command_name {
    my $self = shift;
    my $class = ref($self) || $self;
    return 'workflow' if $class eq __PACKAGE__;
    return $self->SUPER::command_name(@_);
}

sub help_brief {
    "modularized commands for Workflow"
}

1;
