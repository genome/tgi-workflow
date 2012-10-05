
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

sub init {
    my $self = shift;
    
    $self->queue([]);
    $self->count(0);
    
    1;
}

sub execute {
    my $self = shift;
    my %params = @_;

    my $op_instance = $params{operation_instance};
    $self->debug_message($op_instance->id . ' ' . $op_instance->operation->name);

    push @{ $self->queue }, [ @params{'operation_instance','edited_input'} ];
    $params{'operation_instance'}->status('scheduled');

    return;
}

sub wait {
    my $self = shift;

    while (scalar @{ $self->queue } > 0) {
        my ($op_instance, $edited_input) = @{ shift @{ $self->queue } };

        if (!defined $self->limit || $self->count < $self->limit) {
            $self->count($self->count + 1);

            $op_instance->current->status('running');
            $op_instance->current->start_time(Workflow::Time->now);
#            $self->status_message('exec/' . $op_instance->id . '/' . $op_instance->operation->name);
            my $outputs;
            eval {
                local $Workflow::DEBUG_GLOBAL=1 if $op_instance->debug_mode;
                $outputs = $op_instance->operation->operation_type->execute(%{ $op_instance->input }, %{ $edited_input });
            };
            if ($@) {
#                warn $@; 
                $op_instance->current->status('crashed');
                
                Workflow::Operation::InstanceExecution::Error->create(
                    execution => $op_instance->current,
                    error => $@
                );
            } else {
                $op_instance->output({ %{ $op_instance->output }, %{ $outputs } });        
                $op_instance->current->status('done');
            }
            $op_instance->current->end_time(Workflow::Time->now);
        }

        $op_instance->completion;
    }

    1;    
}

1;
