
package Workflow::Model::Instance;

use strict;
use warnings;

class Workflow::Model::Instance {
    is_transactional => 0,
    has => [
        workflow_model => { is => 'Workflow::Model', id_by => 'workflow_model_id' },
        operation_instances => { is => 'Workflow::Operation::Instance', is_many => 1 },
        parent_instance => { is => 'Workflow::Operation::Instance', id_by => 'parent_instance_id' },
        parent_instance_wrapped => { is => 'Object::Destroyer', doc => 'Workflow::Operation::Instance objected wrapped by Object::Destroyer' },
        output_cb => { is => 'CODE' },
    ]
};

sub save_instance {
    return Workflow::Model::SavedInstance->create_from_instance(@_);
}

sub incomplete_operation_instances {
    my $self = shift;
    
    my @all_data = $self->operation_instances;

    return grep {
        !$_->is_done
    } @all_data;
}

sub do_completion {
    my $self = shift;
    
    my $output_data = Workflow::Operation::Instance->get(
        operation => $self->workflow_model->get_output_connector,
        model_instance => $self
    );

    my $final_outputs = $output_data->input;
    foreach my $output_name (%$final_outputs) {
        if (UNIVERSAL::isa($final_outputs->{$output_name},'Workflow::Link::Instance')) {
            $final_outputs->{$output_name} = $final_outputs->{$output_name}->left_value;
        }
    }

    my $data = $self->parent_instance;
    $data->output($final_outputs);
    $data->is_done(1);
}

sub delete {
    my $self = shift;
    
    my @all_data = $self->operation_instances;
    foreach (@all_data) {
        $_->delete;
    }

    return $self->SUPER::delete;
}

1;
