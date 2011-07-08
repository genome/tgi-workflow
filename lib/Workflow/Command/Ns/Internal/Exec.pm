package Workflow::Command::Ns::Internal::Exec;

use strict;
use warnings;

use Workflow ();
use Storable qw(nstore_fd fd_retrieve);

class Workflow::Command::Ns::Internal::Exec {
    is  => ['Workflow::Command'],
    has => [
        debug => {
            is => 'Boolean',
            default_value => 0,
            doc => 'set breakpoint as close to user-module execution as possible'
        },
        input_file => {
            shell_args_position => 1,
            doc                 => 'file to read input from'
        },
        output_file => {
            shell_args_position => 2,
            doc => 'file to send output to'
        }        
    ]
};

$Workflow::DEBUG_GLOBAL || 0;  ## suppress dumb warnings

sub execute {
    my $self = shift;

    if ($self->debug) {
        $Workflow::DEBUG_GLOBAL = 1;
    }

    # unserialize and retrieve input
    my $f = $self->input_file;
    open INS, "<$f"
        or die "cannot open $f!"; 
    my $run = fd_retrieve(*INS) or die "cannot retrieve from $f";
    close INS;


    # execute optype
    my $optype = $run->{type};
    my $inputs = $run->{input};

    my $outputs = $optype->execute(%$inputs);

    my $success = 1;

    if (ref($outputs) =~ /HASH/ && exists $outputs->{result}) {
        if (defined $outputs->{result} && $outputs->{result} > 0) {
            $success = 1;
        } else {
            $success = 0;
        }
    }

    ## serialize and send output
    $f = $self->output_file;
    open OUTS, ">$f"
        or die "cannot open $f!";

    nstore_fd($outputs, *OUTS)
        or die "cannot store into $f";

    close OUTS;

    return $success;
}

1;
