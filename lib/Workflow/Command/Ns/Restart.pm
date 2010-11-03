package Cord::Command::Ns::Restart;

use strict;
use warnings;

use Cord ();

class Cord::Command::Ns::Restart {
    is  => ['Cord::Command'],
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
