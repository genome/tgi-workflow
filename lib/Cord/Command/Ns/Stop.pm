package Cord::Command::Ns::Stop;

use strict;
use warnings;

use Cord ();

class Cord::Command::Ns::Stop {
    is  => ['Cord::Command'],
    has => [
        instance_id => {
            shell_args_position => 1,
            doc                 => 'Instance id to stop'
        }
    ]
};

sub execute {
    my $self = shift;

    # TODO bkill anything running then
    # set database status on each operation instance thats not new or successful
    # to Stopped

    # job group cleanup cron will catch anything not running

    return -88;
}

1;
