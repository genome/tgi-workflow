
package Workflow::Executor::Serial;

use strict;

class Workflow::Executor::Serial {
    isa => 'Workflow::Executor',
};

sub execute {
    my $self = shift;
    my %params = @_;

    my $opdata = $params{operation_instance};

    $opdata->current->status('running');
    $opdata->current->start_time(Workflow::Time->now);

    $self->debug_message($opdata->id . ' ' . $opdata->operation->name);
    my $outputs = $opdata->operation->operation_type->execute(%{ $opdata->input }, %{ $params{edited_input} });

    $opdata->output({ %{ $opdata->output }, %{ $outputs } });
    $opdata->current->status('done');
    $opdata->current->end_time(Workflow::Time->now);

    $opdata->completion;

    return;
}

1;
