
package Workflow::Operation::Instance;

use strict;
use warnings;
use Workflow ();

class Workflow::Operation::Instance {
    is_transactional => 0,
    has => [
        operation => { is => 'Workflow::Operation', id_by => 'workflow_operation_id' },
        model_instance => { is => 'Workflow::Model::Instance', id_by => 'workflow_model_instance_id' },
        output => { is => 'HASH' },
        input => { is => 'HASH' },
        store => { is => 'Workflow::Store' },
        output_cb => { is => 'CODE' },
        is_done => { },
        is_running => { },
        is_parallel => { 
            calculate => q|
                $DB::single=1;
                if ($self->operation->can('parallel_by') && 
                    $self->operation->parallel_by && 
                    ref($self->input_value($self->operation->parallel_by)) eq 'ARRAY') {
                    
                    return 1;
                }
                return 0;
            |,
        }
    ]
};

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    

    
    return $self;
}

sub save_instance {
    return Workflow::Operation::SavedInstance->create_from_instance(@_);
}

sub sync {
    my ($self) = @_;
    
    my $store;
    my $walkon = $self;
    do {
        $store = $walkon->store;
        
        unless ($store) {
            $walkon->model_instance->parent_instance;
        }
    } while (!$store);
    
    $DB::single=1;
    
    return $store->sync($self);
}

sub set_input_links {
    my $self = shift;

    my @links = Workflow::Link->get(
        right_operation => $self->operation,
    );

    my %linkage = ();
    
    foreach my $link (@links) {
        my ($opi) = $self->model_instance->operation_instances(
            operation => $link->left_operation
        );
        next unless $opi;
        
        my $linki = Workflow::Link::Instance->create(
            operation_instance => $opi,
            property => $link->left_property
        );
        
        $linkage{ $link->right_property } = $linki;
    }
    
    $self->input({
        %{ $self->input },
        %linkage
    }); 
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
        if (exists $current_inputs{$input_name} && 
            defined $current_inputs{$input_name} ||
            ($self->operation->operation_type->can('default_input') && 
            exists $self->operation->operation_type->default_input->{$input_name})) {
            if (UNIVERSAL::isa($current_inputs{$input_name},'Workflow::Link::Instance')) {
                unless ($current_inputs{$input_name}->operation_instance->is_done && defined $current_inputs{$input_name}->left_value) {
                    push @unfinished_inputs, $input_name;
                }
            }
        } else {
            push @unfinished_inputs, $input_name;
        }
    }

    if (scalar @unfinished_inputs == 0) {
        return 1;
    } else {
        return 0;
    }
}

sub child_model_instances {
    my ($self) = @_;
    
    return unless ($self->operation->operation_type->isa('Workflow::OperationType::Model'));
    
    my @model_instances = Workflow::Model::Instance->get(
        workflow_model => $self->operation,
        parent_instance => $self
    );

    return @model_instances;
}

sub incomplete_child_model_instances {
    my $self = shift;
    
    return grep {
        my $outconn_i = Workflow::Operation::Instance->get(
            model_instance => $_,
            operation => $_->workflow_model->get_output_connector
        );
        !$outconn_i->is_done;
    } $self->child_model_instances;
}

sub input_value {
    my ($self, $input_name) = @_;
    
    return undef unless $self->input->{$input_name};
    
    if (UNIVERSAL::isa($self->input->{$input_name},'Workflow::Link::Instance')) {
        return $self->input->{$input_name}->left_value;
    } else {
        return $self->input->{$input_name};
    }
}

sub execute {
    my $self = shift;

#    $self->status_message("exec/" . $self->id . "/" . $self->operation->name);

#    print ref($self->model_instance->workflow_model->executor) . "\n"
#        if ($self->model_instance);

    if ($self->operation->operation_type->isa('Workflow::OperationType::Model')) {

        if ($self->is_parallel) {
            for (my $i = 0; $i < scalar @{ $self->input_value($self->operation->parallel_by) }; $i++) {
                Workflow::Model::Instance->create(
                    workflow_model => $self->operation,
                    parent_instance => $self,
                    parallel_index => $i
                );
            }
        } else {
            Workflow::Model::Instance->create(
                workflow_model => $self->operation,
                parent_instance => $self
            );
        }
        $self->sync;
        
        my @child_mi = $self->child_model_instances;
        foreach my $child_mi (@child_mi) {
            my @runq = $child_mi->runq;
            foreach my $this_data (@runq) {
                $this_data->is_running(1);
            }

            foreach my $this_data (@runq) {
                $this_data->execute;
            }
        }
        
    } else {
        $self->sync;
        
        my %current_inputs = ();
        foreach my $input_name (keys %{ $self->input }) {
            if (UNIVERSAL::isa($self->input->{$input_name},'Workflow::Link::Instance')) {
                $current_inputs{$input_name} = $self->input->{$input_name}->left_value;
                while (UNIVERSAL::isa($current_inputs{$input_name},'Workflow::Link::Instance')) {
                    $current_inputs{$input_name} = $current_inputs{$input_name}->left_value;
                }
            }
        }

        my $executor = $self->operation->executor || $self->operation->workflow_model->executor;
        my $operation_type = $self->operation->operation_type;
        if ($operation_type->can('executor') && defined $operation_type->executor) {
            $executor = $operation_type->executor;
        }

        $executor->execute(
            operation_instance => $self,
            edited_input => \%current_inputs
        );
        
    }
}

sub dependent_operations {
    my ($self) = @_;

    my %uniq_deps = map {
        my ($this_data) = Workflow::Operation::Instance->get(
            operation => $_,
            model_instance => $self->model_instance
        );
        $_->name => $this_data
    } $self->operation->dependent_operations;

    return values %uniq_deps;
}

sub completion {
    my $self = shift;
    my $model_instance = shift;

    $self->sync;
    
    if ($model_instance) {
        # a specific child has completed
        my @incomplete_children = $self->incomplete_child_model_instances;
        
        unless (@incomplete_children) {
            $self->is_done(1);
            $self->output_cb->($self,$model_instance)
                if (defined $self->output_cb);
            $self->sync;
            $model_instance->delete;
            
            # let fall through to operation completion code below
        } else {
            return;
        }
    }    
    
    if ($model_instance = $self->model_instance) {
        $self->is_running(0);

        my $model = $self->model_instance->workflow_model;

        my @incomplete_operations = $model_instance->incomplete_operation_instances;

        if (@incomplete_operations) {
            my @runq = $model_instance->runq_filter($self->dependent_operations);

            foreach my $this_data (@runq) {
                $this_data->is_running(1);
            }

            foreach my $this_data (@runq) {
                $this_data->execute;
            }        
        } else {
            $model_instance->completion;
        }
        
    }

    if (!$model_instance) {
        $self->is_done(1);
        $self->output_cb->($self)
            if (defined $self->output_cb);
        $self->sync;
    }

    return;
}

1;
