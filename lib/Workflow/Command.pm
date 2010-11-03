
package Cord::Command;

use strict;
use warnings;
use Cord;

class Cord::Command {
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
    "modularized commands for Cord"
}

1;
