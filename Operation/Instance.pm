
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
        is_done => { },
        is_running => { },
    ]
};

sub save_instance {
    return Workflow::Operation::SavedInstance->create_from_instance(@_);
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

sub execute {
    my $self = shift;

    $self->status_message("opie/" . $self->id . "/" . $self->operation->name);

    $self->operation->Workflow::Operation::execute($self);
}

sub do_completion {
    my $self = shift;
    
    $self->model_instance->workflow_model->operation_completed($self);
}

1;
