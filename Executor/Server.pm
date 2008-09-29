
package Workflow::Executor::Server;

use strict;
use POE;

class Workflow::Executor::Server {
    isa => 'Workflow::Executor',
    has => [
        server => { is => 'Workflow::Server' }
    ]
};

sub execute {
    my $self = shift;
    my %params = @_;

#    $self->status_message('OExec ' . $params{operation_instance}->operation->name);
    $self->server->run_operation(
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
