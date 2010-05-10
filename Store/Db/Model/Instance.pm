 
package Workflow::Store::Db::Model::Instance;

use strict;
use warnings;

# these should not be necessary
# remove when rt56577 is done
use Workflow::Operation::Instance;
use Workflow::Model::Instance;

class Workflow::Store::Db::Model::Instance { 
    isa => [ 'Workflow::Store::Db::Operation::Instance' ],
    has => [
        child_instances => { is => 'Workflow::Store::Db::Operation::Instance', is_many => 1, reverse_id_by => 'parent_instance' },
        ordered_child_instances => { 
            is => 'Workflow::Store::Db::Operation::Instance', 
            is_many => 1,
            calculate => q{ $self->sorted_child_instances } 
        },
        input_connector => { is => 'Workflow::Store::Db::Operation::Instance', id_by => 'input_connector_id' },
        output_connector => { is => 'Workflow::Store::Db::Operation::Instance', id_by => 'output_connector_id' },
    ]
};

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
