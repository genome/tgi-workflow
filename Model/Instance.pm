
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
        parallel_index => { }
    ]
};

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    
    my $parent = $self->parent_instance;

    my %input = %{ $parent->input };
    if (defined $self->parallel_index) {
        $input{ $parent->operation->parallel_by() } = 
            $parent->input_value($parent->operation->parallel_by)->[$self->parallel_index];
    }

    my @all_opi;
    foreach ($self->workflow_model->operations) {
        my $this_data = Workflow::Operation::Instance->create(
            operation => $_,
            model_instance => $self,
            is_done => 0,
            store => $parent->store
        );
        $this_data->input({});
        $this_data->output({});
        if ($_ == $self->workflow_model->get_input_connector) {
            $this_data->output(
                \%input
            );
        }
        push @all_opi, $this_data;
    }
    foreach (@all_opi) {
        $_->set_input_links;
    }
    
    return $self;
}

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

sub resume {
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

sub completion {
    my $self = shift;
        
    my $output_data = Workflow::Operation::Instance->get(
        operation => $self->workflow_model->get_output_connector,
        model_instance => $self
    );

    my $parent = $self->parent_instance;
    my $poutputs = $parent->output;

    my $final_outputs = $output_data->input;
    foreach my $output_name (keys %$final_outputs) {
        while (UNIVERSAL::isa($final_outputs->{$output_name},'Workflow::Link::Instance')) {
            $final_outputs->{$output_name} = $final_outputs->{$output_name}->left_value;
        }
        
        if (defined $self->parallel_index) {
            $poutputs->{$output_name} ||= [];
            $poutputs->{$output_name}->[ $self->parallel_index ] = $final_outputs->{$output_name};
        } else {
            $poutputs->{$output_name} = $final_outputs->{$output_name};
        }
    }
    $parent->output($poutputs);
    $parent->completion($self);
}

sub runq {
    my $self = shift;

    return $self->runq_filter($self->operation_instances);
}

sub runq_filter {
    my $self = shift;
    
    my @runq = sort {
        $a->operation->name cmp $b->operation->name
    } grep {
        $_->is_ready &&
        !$_->is_done &&
        !$_->is_running
    } @_;
    
    return @runq;
}

sub sync {
    my ($self) = @_;
    
    Carp::carp("sync on this class deprecated");
    
    return $self->parent_instance->store->sync($self);
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
