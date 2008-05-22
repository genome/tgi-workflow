
package Workflow::Operation::Data;

use strict;
use warnings;

class Workflow::Operation::Data {
    is_transactional => 0,
    has => [
        operation => { is => 'Workflow::Operation', id_by => 'workflow_operation_id' },
        dataset => { is => 'Workflow::Operation::DataSet', id_by => 'workflow_operation_dataset_id' },
        output => { is => 'HASH' },
        input => { is => 'HASH' },
        is_done => { },
    ]
};

sub set_input_links {
    my $self = shift;
    
    my @links = Workflow::Link->get(
        right_operation => $self->operation,
    );
    
    foreach my $link (@links) {
        $self->input({
            %{ $self->input },
            $link->right_property => $link
        }); 
    }
}

sub is_ready {
    my $self = shift;

    my @required_inputs = @{ $self->operation->operation_type->input_properties };
    my %current_inputs = ();
    if ( defined $self->input ) {
        %current_inputs = %{ $self->input };
    }

    my @unfinished_inputs = ();
    foreach my $input_name (@required_inputs) {
        if (exists $current_inputs{$input_name} && defined $current_inputs{$input_name}) {
            if (UNIVERSAL::isa($current_inputs{$input_name},'Workflow::Link')) {
                unless ($current_inputs{$input_name}->left_data($self->dataset)->is_done && $current_inputs{$input_name}->left_value($self->dataset)) {
                    push @unfinished_inputs, $input_name;
                }
            }
        } else {
            push @unfinished_inputs, $input_name;
        }
    }
    if (scalar @unfinished_inputs > 0) {
        $self->debug_message($self->operation->name . " still needs: " . join(',', @unfinished_inputs))
    } else {
        $self->debug_message($self->operation->name . ' is ready');
    }

    if (scalar @unfinished_inputs == 0) {
        return 1;
    } else {
        return 0;
    }
}

1;
