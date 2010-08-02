package Workflow::Command::Ns::Internal::Exit;

use strict;
use warnings;

use Workflow ();

class Workflow::Command::Ns::Internal::Exit {
    is  => ['Workflow::Command'],
    has => [
        instance_id => {
            shell_args_position => 1,
            doc                 => 'Instance id that had an operation exit'
        }
    ]
};

sub execute {
    my $self = shift;

    # load workflow
    # find running sub workflows with crashed events
    # if no other event running, set workflow crashed
    # walk upward to parent

    # if things claim to be running, compare bjobs -g 
    # to database list
    # when bad status found
    #  lock row, change status

    # if actually running, sleep 30 seconds after all checks are done
    # reload operations that were in running, scheduled or new

    # when nothing else is running but us, kill pending jobs
    # that will never have deps satisfied
    # kill done handler

    # exit successfully so user-defined handler runs 

    1;
}

1;
