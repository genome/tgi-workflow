
package Workflow::Operation::DataSet;

use strict;
use warnings;

class Workflow::Operation::DataSet {
    is_transactional => 0,
    has => [
        workflow_model => { is => 'Workflow::Model', id_by => 'workflow_model_id' },
        operation_datas => { is => 'Workflow::Operation::Data', is_many => 1 },
        parent_data => { is => 'Workflow::Operation::Data', id_by => 'parent_data_id' },
        output_cb => { is => 'CODE' },
    ]
};

sub incomplete_operation_data {
    my $self = shift;
    
    my @all_data = $self->operation_datas;

    return grep {
        !$_->is_done
    } @all_data;
}

sub do_completion {
    my $self = shift;
    
    my $output_data = Workflow::Operation::Data->get(
        operation => $self->workflow_model->get_output_connector,
        dataset => $self
    );

    my $final_outputs = $output_data->input;
    foreach my $output_name (%$final_outputs) {
        if (UNIVERSAL::isa($final_outputs->{$output_name},'Workflow::Link')) {
            $final_outputs->{$output_name} = $final_outputs->{$output_name}->left_value($self);
        }
    }

    my $data = $self->parent_data;
    $data->output($final_outputs);
    $data->is_done(1);
    
    my @all_data = $self->operation_datas;
    foreach (@all_data) {
        $_->delete;
    }
}

1;
