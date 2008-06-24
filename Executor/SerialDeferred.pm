
package Workflow::Executor::SerialDeferred;

use strict;

class Workflow::Executor::SerialDeferred {
    isa => 'Workflow::Executor',
    is_transactional => 0,
    has => [
        queue => { is => 'ARRAY' }
    ]
};

sub execute {
    my $self = shift;
    my %params = @_;

    unless (defined $self->queue) {
        $self->queue([]);
    }

    push @{ $self->queue }, [ @params{'operation_instance','edited_input'} ];

    return;
}

sub wait {
    my $self = shift;

    while (scalar @{ $self->queue } > 0) {

        my ($opdata, $edited_input) = @{ shift @{ $self->queue } };

        $self->status_message('exec/' . $opdata->model_instance->id . '/' . $opdata->operation->name);
        my $outputs = $opdata->operation->operation_type->execute(%{ $opdata->input }, %{ $edited_input });

        $opdata->output({ %{ $opdata->output }, %{ $outputs } });
        $opdata->is_done(1);

        $opdata->do_completion;

        $DB::single=1;

    }
    
}

1;
