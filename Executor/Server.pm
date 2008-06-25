
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
    
    if ($params{operation_instance}->operation->isa('Workflow::Model')) {
        my $submodel = $params{operation_instance}->operation;
        
        my $opi = $params{operation_instance};
        $submodel->executor($self);
        
        my $cb = sub {
            my ($data) = @_;
            
            $opi->output({ %{ $opi->output }, %{ $data->output } });
            $opi->is_done(1);
            $opi->do_completion;
        };
        
        my $newinstance = $submodel->execute(
            input => {
                %{ $opi->input },
                %{ $params{edited_input} }
            },
            output_cb => $cb
        );

        $submodel->wait;
        
    } else {
        $self->server->run_operation(
            $params{operation_instance},
            $params{edited_input}
        );
    }

    return;
}

1;
