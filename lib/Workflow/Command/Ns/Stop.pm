package Workflow::Command::Ns::Stop;

use strict;
use warnings;

use Workflow ();

class Workflow::Command::Ns::Stop {
    is  => ['Workflow::Command'],
    has => [
        instance_id => {
            shell_args_position => 1,
            doc                 => 'Instance id to stop'
        }
    ]
};

sub execute {
    my $self = shift;

    # bkill the exit handler in the job group, dont care about it
    # bkill all the other jobs

    # wait for jobs to die

    # set database status on each operation instance thats not new or successful
    # to Stopped

    return -88;
}

1;
