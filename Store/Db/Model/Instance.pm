 
package Workflow::Store::Db::Model::Instance;

use strict;
use warnings;
use Workflow::Model::Instance;

use Workflow ();
class Workflow::Store::Db::Model::Instance { 
    isa => [ 'Workflow::Store::Db::Operation::Instance' ],
    has => [
        child_instances => { is => 'Workflow::Store::Db::Operation::Instance', is_many => 1, reverse_id_by => 'parent_instance' },
        input_connector => { is => 'Workflow::Store::Db::Operation::Instance', id_by => 'input_connector_id' },
        output_connector => { is => 'Workflow::Store::Db::Operation::Instance', id_by => 'output_connector_id' },
    ]
};

sub operation_instance_class_name {
    'Workflow::Store::Db::Operation::Instance'
}

sub model_instance_class_name {
    'Workflow::Store::Db::Model::Instance'
}

sub instance_execution_class_name {
    'Workflow::Store::Db::Operation::InstanceExecution'
}

sub sorted_child_instances {
    goto &Workflow::Model::Instance::sorted_child_instances;
}

sub create {
    goto &Workflow::Model::Instance::create;
}

sub incomplete_operation_instances {
    goto &Workflow::Model::Instance::incomplete_operation_instances;
}

sub resume {
    goto &Workflow::Model::Instance::resume;
}

sub execute {
    goto &Workflow::Model::Instance::execute;
}

sub execute_single {
    goto &Workflow::Model::Instance::execute_single;
}

sub completion {
    goto &Workflow::Model::Instance::completion;
}

sub reset_current {
    goto &Workflow::Model::Instance::reset_current;
}

sub runq {
    goto &Workflow::Model::Instance::runq;
}

sub runq_filter {
    goto &Workflow::Model::Instance::runq_filter;
}

sub delete {
    goto &Workflow::Model::Instance::delete;
}

1;
