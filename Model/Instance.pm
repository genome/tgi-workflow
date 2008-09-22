
package Workflow::Model::Instance;

use strict;
use warnings;

class Workflow::Model::Instance {
    isa => 'Workflow::Operation::Instance',
    has => [
        child_instances => { is => 'Workflow::Operation::Instance', is_many => 1, reverse_id_by => 'parent_instance' },
        input_connector => { is => 'Workflow::Operation::Instance', id_by => 'input_connector_id' },
        output_connector => { is => 'Workflow::Operation::Instance', id_by => 'output_connector_id' },
    ]
};

#map { print "$_\n" } keys %Workflow::Model::Instance::;

sub sorted_child_instances {
    my $self = shift;

    my $i = 0;
    my %ops = map { 
        $_->name() => $i++
    } $self->operation->operations_in_series();
            
    my @child = sort {
        $ops{ $a->operation->name } <=> $ops{ $b->operation->name } || 
        $a->operation->name cmp $b->operation->name || 
        $a->parallel_index <=> $b->parallel_index
    } $self->child_instances(@_);
    
    return @child;
}

sub create {
    my $class = shift;
    my %args = (@_);
    my $load = delete $args{load_mode};
    my $self = $class->SUPER::create(%args);

    return $self if $load;
    
    my $operation_class_name = $self->operation_instance_class_name;
    
    my @all_opi;
    foreach ($self->operation->operations) {
        my $this_data = $operation_class_name->create(
            operation => $_,
            parent_instance => $self,
            store => $self->store
        );
        $this_data->input({});
        $this_data->output({});
        push @all_opi, $this_data;
    }
    foreach (@all_opi) {
        $_->set_input_links;
    }
    
    $self->input_connector(Workflow::Operation::Instance->get(
        operation => $self->operation->get_input_connector,
        parent_instance => $self
    ));
    
    $self->output_connector(Workflow::Operation::Instance->get(
        operation => $self->operation->get_output_connector,
        parent_instance => $self
    ));
    
    return $self;
}

sub incomplete_operation_instances {
    my $self = shift;
    
    my @all_data = $self->child_instances;

    return grep {
        !$_->is_done
    } @all_data;
}

sub resume {
    my $self = shift;

    die 'tried to resume a finished operation' if ($self->is_done);

        
    die 'nf';
return;
=pod
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
=cut
}

sub execute {
    my $self = shift;

    $self->current->start_time(UR::Time->now);
    $self->current->status('running');
    $self->is_running(1);

    $self->input_connector->output($self->input);
    $self->SUPER::execute;
}

sub execute_single {
    my $self = shift;

    my @runq = $self->runq;
    foreach my $this_data (@runq) {
        $this_data->is_running(1);
    }

    foreach my $this_data (@runq) {
        $this_data->execute;
    }
}

sub completion {
    my $self = shift;

    my $oc = $self->output_connector;
    foreach my $output_name (keys %{ $oc->input }) {
        if (ref($oc->input->{$output_name}) eq 'ARRAY') {
            my @new = map {
                UNIVERSAL::isa($_,'Workflow::Link::Instance') ?
                    $_->value : $_
            } @{ $oc->input->{$output_name} };
            $self->output->{$output_name} = \@new;
        } else {
            $self->output->{$output_name} = $oc->input_value($output_name);
        }
    }

    $self->current->end_time(UR::Time->now);
    $self->current->status('done') if ($self->current->status eq 'running');

    $self->SUPER::completion;
}

sub runq {
    my $self = shift;

    return $self->runq_filter($self->child_instances);
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

sub delete {
    my $self = shift;
    
    my @all_data = $self->operation_instances;
    foreach (@all_data) {
        $_->delete;
    }

    return $self->SUPER::delete;
}

1;
