
package Workflow::Executor::Server;

use strict;

class Workflow::Executor::Server {
    isa => 'Workflow::Executor'
};

sub execute {
    my $self = shift;
    my %params = @_;

    my $opdata = $params{operation_instance};
    $self->debug_message($opdata->id . ' ' . $opdata->operation->name);

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
