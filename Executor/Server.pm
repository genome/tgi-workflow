
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

## session selection code needs to go here or somewhere.
    my $session = $self->server->{workers}->[0];
    
    my $op = $params{operation};
    my $opdata = $params{operation_data};
    my $callback = $params{output_cb};

    $self->status_message('exec/' . $opdata->dataset->id . '/' . $op->name);
    $poe_kernel->post(
        $session, 'send_operation', $op, $opdata, $params{edited_input}, sub { $callback->($opdata) }
    );


    return;
}

1;
