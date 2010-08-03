package Workflow::Command::Ns::Internal::Exec;

use strict;
use warnings;

use Workflow ();
use Storable qw(store_fd fd_retrieve);

class Workflow::Command::Ns::Internal::Exec {
    is  => ['Workflow::Command'],
    has => [
        input_fd => {
            shell_args_position => 1,
            doc                 => 'file descriptor number to read input from'
        },
        output_fd => {
            shell_args_position => 2,
            doc => 'file descriptor to send output to'
        }        
    ]
};

sub execute {
    my $self = shift;

    # unserialize and retrieve input
    my $fd = $self->input_fd;
    open INS, "<&=$fd"
        or die "cannot open $fd!"; 
    my $run = fd_retrieve(*INS) or die "cannot retrieve from fd $fd";
    close INS;


    # execute optype
    my $optype = $run->{type};
    my $inputs = $run->{input};

#    my $outputs = $optype->execute(%$inputs);

    my $outputs = { abc => 123 };

    ## serialize and send output
    $fd = $self->output_fd;
    open OUTS, ">&=$fd"
        or die "cannot open $fd!";

    store_fd($outputs, *OUTS)
        or die "cannot store into fd $fd";

    close OUTS;

    -1;
}

1;
