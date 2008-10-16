
package Workflow::Executor::SerialDeferred;

use strict;

class Workflow::Executor::SerialDeferred {
    isa => 'Workflow::Executor',
    has => [
        queue => { is => 'ARRAY', default_value => [] },
        limit => { is => 'Integer', doc => 'Count of operations to run', is_optional => 1 },
        count => { is => 'Integer', doc => 'Number run so far', default_value => 0 },
    ]
};

sub execute {
    my $self = shift;
    my %params = @_;

    unless (defined $self->queue) {
        $self->queue([]);
    }

    push @{ $self->queue }, [ @params{'operation_instance','edited_input'} ];

    $params{'operation_instance'}->status('scheduled');

    return;
}

sub wait {
    my $self = shift;

    while (scalar @{ $self->queue } > 0) {
        my ($opdata, $edited_input) = @{ shift @{ $self->queue } };

        if (!defined $self->limit || $self->count < $self->limit) {
            $self->count($self->count + 1);

            $opdata->current->status('running');
            $opdata->current->start_time(UR::Time->now);
#            $self->status_message('exec/' . $opdata->id . '/' . $opdata->operation->name);
            my $outputs;
            eval {
                local $Workflow::DEBUG_GLOBAL=1 if $opdata->debug_mode;
                $outputs = $opdata->operation->operation_type->execute(%{ $opdata->input }, %{ $edited_input });
            };
            if ($@) {
#                warn $@; 
                $opdata->current->status('crashed');
                
                Workflow::Operation::InstanceExecution::Error->create(
                    execution => $opdata->current,
                    error => $@
                );
            } else {
                $opdata->output({ %{ $opdata->output }, %{ $outputs } });        
                $opdata->current->status('done');
            }
            $opdata->current->end_time(UR::Time->now);
        }

        $opdata->completion;
    }

    1;    
}

1;
