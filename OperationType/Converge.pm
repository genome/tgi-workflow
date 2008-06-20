
package Workflow::OperationType::Converge;

use strict;
use warnings;

class Workflow::OperationType::Converge {
    isa => 'Workflow::OperationType',
    has => [
        executor => { is => 'Workflow::Executor', id_by => 'workflow_executor_id' },
    ]
};

sub create {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::create(%args);
    my $serial_executor = Workflow::Executor::Serial->create;
    $self->executor($serial_executor);

    return $self;
}

sub execute {
    my $self = shift;
    my %properties = @_;

    my $output = [];
    foreach my $input_property (@{ $self->input_properties }) {
        if (ref($properties{$input_property}) eq 'ARRAY') {
            push @$output, @{ $properties{$input_property} };
        } else {
            push @$output, $properties{$input_property};
        }
    }

    my ($output_name) = @{ $self->output_properties };

    return {
        $output_name => $output
    };
}

1;
