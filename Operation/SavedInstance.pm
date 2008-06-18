package Workflow::Operation::SavedInstance;

use strict;
use warnings;
use Storable qw(freeze thaw);

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
    
    my $self = $class->create;

    $self->input(freeze $unsaved->input);
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
    
    $unsaved->input(thaw $self->input);
    $unsaved->output(thaw $self->output);
    $unsaved->is_done($self->is_done);
    $unsaved->is_running($self->is_running);
    
    return $unsaved;
}

1;
