
package Workflow::OperationType::Converge;

use strict;
use warnings;

class Workflow::OperationType::Converge {
    isa => 'Workflow::OperationType',
    has => [
        stay_in_process => {
            value => 1
        }        
    ]
};

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

    my @output_values = map {
        UNIVERSAL::isa($_,'Workflow::Link::Instance') ? $_->value : $_
    } @$output;

    my ($output_name) = @{ $self->output_properties };

    return {
        $output_name => \@output_values,
        result => 1
    };
}

1;
