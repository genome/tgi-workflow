
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

    ## delegate back to the server
    
    if ($params{operation_instance}->operation->isa('Workflow::Model')) {
        $self->status_message('MExec ' . $params{operation_instance}->operation->name);
        my $submodel = $params{operation_instance}->operation;
        
        my $opi = $params{operation_instance};
        $submodel->executor($self);
        
        my $cb = sub {
            my ($data) = @_;
            
            $opi->output({ %{ $opi->output }, %{ $data->output } });
            $opi->is_done(1);
            $opi->completion;
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
        $self->status_message('OExec ' . $params{operation_instance}->operation->name);
        $self->server->run_operation(
            $params{operation_instance},
            $params{edited_input}
        );
    }

    return;
}

1;
