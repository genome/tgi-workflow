
package Workflow::Executor::Server;

use strict;
use POE;

class Workflow::Executor::Server {
    isa => 'Workflow::Executor',
    has => [
        server => { is => 'Workflow::Server', is_optional => 1 }
    ]
};

sub execute {
    my $self = shift;
    my %params = @_;

    Workflow::Server::UR->dispatch(
        $params{operation_instance},
        $params{edited_input}
    );

    return;
}

sub exception {
    my ($self, $instance, $message) = @_;
    
    $instance->sync;
    
    # dont do anything here, should drop it out of the execution loop.
}

1;
