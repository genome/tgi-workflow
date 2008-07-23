package Workflow::Operation::SavedInstance;

use strict;
use warnings;
use Storable qw(freeze thaw);
use Workflow::Link::SavedInstance;

class Workflow::Operation::SavedInstance {
    type_name => 'operation saved instance',
    table_name => 'OPERATION_SAVED_INSTANCE',
    id_by => [
        operation_instance_id => { is => 'INTEGER' },
    ],
    has => [
        input                 => { is => 'BLOB', is_optional => 1 },
        is_done               => { is => 'INTEGER', is_optional => 1 },
        is_running            => { is => 'INTEGER', is_optional => 1 },
        model_instance        => { is => 'Workflow::Model::SavedInstance', id_by => 'model_instance_id' },
        model_instance_id     => { is => 'INTEGER', is_optional => 1 },
        operation             => { is => 'TEXT' },
        output                => { is => 'BLOB', is_optional => 1 },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

sub create_from_instance {
    my ($class, $unsaved, $model_saved_instance) = @_;
    
    my $self = $class->get(
        operation => $unsaved->operation->name,
        model_instance_id => $unsaved->model_instance ? $model_saved_instance->id : undef
    );
        
    unless ($self) {
        $self = $class->create;
    }

    my $newinput = {};
    while (my ($key, $value) = each(%{ $unsaved->input })) {
        my $newvalue = $value;
        if (UNIVERSAL::isa($value,'Workflow::Link::Instance')) {
            $newvalue = Workflow::Link::SavedInstance->create_from_instance($value);
            
        }
        $newinput->{$key} = $newvalue;
    }

    $self->input(freeze $newinput);
    $self->output(freeze $unsaved->output);
    $self->operation($unsaved->operation->name);
    $self->is_done($unsaved->is_done);
    $self->is_running($unsaved->is_running);

    if ($unsaved->model_instance) {
        unless ($model_saved_instance) {
            die 'model_saved_instance not passed but unsaved has model_instance';
        }
        $self->model_instance($model_saved_instance);
    }
    
    return $self;
}

## this is here to help solve out of order loading
my $link_load_queue = [];

sub load_instance {
    my $self = shift;
    my $model = shift; ## the real Workflow::Model, not an instance of execution
    my $model_instance_unsaved = shift;
    
    my $operation;
    if ($model_instance_unsaved) {
        $operation = Workflow::Operation->get(
            name => $self->operation,
            workflow_model => $model
        );
    } else {
        $operation = $model;
    }
    
    my %opts = ();
    if ($model_instance_unsaved) {
        $opts{model_instance} = $model_instance_unsaved;
    }
    my $unsaved = Workflow::Operation::Instance->get_or_create(
        operation => $operation,
        %opts
    );
    
    my $inputs = thaw $self->input;
    while (my ($key, $value) = each(%{ $inputs })) {
        my $newvalue = $value;
        if (UNIVERSAL::isa($value,'Workflow::Link::SavedInstance')) {
            my $link = $value->load_instance($model_instance_unsaved);
            
            if (defined $link) {
                $newvalue = $link;
            } else {
                $newvalue = undef;
                
                push @$link_load_queue, [$unsaved, $key, $value];
            }
            
        }
        $inputs->{$key} = $newvalue;
    }    
    
    $unsaved->input($inputs);
    
    $unsaved->output(thaw $self->output);
    $unsaved->is_done($self->is_done);
    $unsaved->is_running($self->is_running);
    
    _link_load_queue();
    
    return $unsaved;
}

sub _link_load_queue {
    my $new_queue = [];
    $DB::single=1;
    while (scalar (@$link_load_queue)) {
        my ($unsaved, $property, $link) = @{ shift @$link_load_queue };
        my $unsaved_link = $link->load_instance($unsaved->model_instance);
        
        if ($unsaved_link) {
            $unsaved->input({
                %{ $unsaved->input },
                $property => $unsaved_link
            });
        } else {
            push @$new_queue, [$unsaved,$property,$link];
        }
    }
    $link_load_queue = $new_queue;
}

1;
