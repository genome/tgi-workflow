package Workflow::Model::SavedInstance;

use strict;
use warnings;

use Workflow;
class Workflow::Model::SavedInstance {
    type_name => 'model saved instance',
    table_name => 'MODEL_SAVED_INSTANCE',
    id_by => [
        model_instance_id => { is => 'INTEGER' },
    ],
    has => [
        model              => { is => 'TEXT' },
        parent_instance_id => { is => 'INTEGER' },
        parent_instance => { is => 'Workflow::Operation::SavedInstance', id_by => 'parent_instance_id' },
        operation_instances => { is => 'Workflow::Operation::SavedInstance', is_many => 1, reverse_id_by => 'model_instance' },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

sub create_from_instance {
    my ($class, $unsaved) = @_;
    
    my $self = $class->create;
    
    $self->model($unsaved->workflow_model->name);
    $self->parent_instance($unsaved->parent_instance->save_instance);

    foreach my $opi ($unsaved->operation_instances) {
        $opi->save_instance($self);
    }
    
    return $self;
}

sub load_instance {
    my $self = shift;
    my $model = shift; ## the real Workflow::Model to attach to
    
    my $unsaved = Workflow::Model::Instance->create;
    $unsaved->parent_instance($self->parent_instance->load_instance);
    
    $unsaved->workflow_model($model);
    
    foreach my $opsi ($self->operation_instances) {
        $opsi->load_instance($model,$unsaved);
    }
    
    return $unsaved;
}

1;
