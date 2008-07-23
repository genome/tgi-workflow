
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
        store => { is => 'Workflow::Store' },
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

sub resume_execution {
    my $self = shift;
    
    foreach my $this ($self->operation_instances) {
        $this->is_running(0) if ($this->is_running);
    }
    
    my @runq = $self->workflow_model->runq_from_operation_instance_list($self->operation_instances);

    foreach my $this_data (@runq) {
        $this_data->is_running(1);
    }

    foreach my $this_data (@runq) {
        $this_data->execute;
    }
    
    return $self->parent_instance;
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
    
    $self->sync;
}

sub sync {
    my ($self) = @_;
    
    return $self->store->sync($self);
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
