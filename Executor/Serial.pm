
package Workflow::Executor::Serial;

use strict;

class Workflow::Executor::Serial {
    isa => 'Workflow::Executor',
    is_transactional => 0
};

sub execute {
    my $self = shift;
    my %params = @_;

    my $op = $params{operation};
    my $opdata = $params{operation_data};
    my $callback = $params{output_cb};

    $self->status_message('exec/' . $opdata->dataset->id . '/' . $op->name);
    my $outputs = $op->operation_type->execute(%{ $opdata->input }, %{ $params{edited_input} });

    $opdata->output({ %{ $opdata->output }, %{ $outputs } });
    $opdata->is_done(1);

    $callback->($opdata);

    return;
}

1;
