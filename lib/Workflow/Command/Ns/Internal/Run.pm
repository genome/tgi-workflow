package Workflow::Command::Ns::Internal::Run;

use strict;
use warnings;

use Workflow ();

class Workflow::Command::Ns::Internal::Run {
    is  => ['Workflow::Command'],
    has => [
        instance_id => {
            shell_args_position => 1,
            doc                 => 'Instance id to run'
        }
    ]
};

sub execute {
    my $self = shift;

    print $self->instance_id . "\n";

    # load operation
    # lock row
    # gather inputs from previous
    # set status running
    # commit
    # run operation_type
    # lock row
    # set status success, crashed or failed
    # commit
    #
    # if crashed or failed and retry count is low
    # set status scheduled
    # commit
    # exit code 88

    # if successful and i'm output connector
    # lock parent workflow
    # set parent workflow status to successful
    # copy my inputs to parent workflow outputs
    # commit

    # exit successfully
    1;
}

1;
