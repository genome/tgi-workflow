
package Workflow::Executor::Serial;

use strict;

class Workflow::Executor::Serial {
    isa => 'Workflow::Executor',
    is_transactional => 0
};

sub execute {
    my $self = shift;
    my %params = @_;

    my $opdata = $params{operation_instance};

#    $self->status_message('exec/' . $opdata->dataset->id . '/' . $op->name);
    my $outputs = $opdata->operation->operation_type->execute(%{ $opdata->input }, %{ $params{edited_input} });

    $opdata->output({ %{ $opdata->output }, %{ $outputs } });
    $opdata->is_done(1);

    $opdata->do_completion;

    return;
}

1;
