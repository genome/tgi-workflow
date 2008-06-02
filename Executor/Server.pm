
package Workflow::Executor::Server;

use strict;
use POE;

class Workflow::Executor::Server {
    isa => 'Workflow::Executor',
    is_transactional => 0,
    has => [
        server => { is => 'Workflow::Server' }
    ]
};

sub execute {
    my $self = shift;
    my %params = @_;

    ## delegate back to the server
    
    $self->server->run_operation(
        $params{operation_data},
        sub { $params{output_cb}->($params{operation_data}) },
        $params{edited_input}
    );

    return;
}

1;
