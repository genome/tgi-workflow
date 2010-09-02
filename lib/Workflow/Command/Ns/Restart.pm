package Workflow::Command::Ns::Restart;

use strict;
use warnings;

use Workflow ();

class Workflow::Command::Ns::Restart {
    is  => ['Workflow::Command'],
    has => [
        instance_id => {
            shell_args_position => 1,
            doc                 => 'Instance id to restart'
        }
    ]
};

sub execute {
    my $self = shift;

    # see if anything is running
    # call stop command

    # TODO    

    1;
}

1;
