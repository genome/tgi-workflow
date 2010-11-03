
package Cord::Executor::Server;

use strict;

class Cord::Executor::Server {
    isa => 'Cord::Executor'
};

sub execute {
    my $self = shift;
    my %params = @_;

    my $opdata = $params{operation_instance};
    $self->debug_message($opdata->id . ' ' . $opdata->operation->name);

    Cord::Server::UR->dispatch(
        $params{operation_instance},
        $params{edited_input}
    );

    return;
}

sub exception {
    my ($self, $instance, $message) = @_;
    
    # dont do anything here, should drop it out of the execution loop.
}

1;
