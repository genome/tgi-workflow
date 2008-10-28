
package Workflow::Operation::InstanceExecution;

use strict;
use warnings;

class Workflow::Operation::InstanceExecution {
    sub_classification_method_name => '_resolve_subclass_name',
    has => [
        operation_instance => { is => 'Workflow::Operation::Instance', id_by => 'instance_id' },
        status => { },
        start_time => { },
        end_time => { },
        exit_code => { },
        stdout => { },
        stderr => { },
        is_done => { is => 'Boolean' },
        is_running => { is => 'Boolean' },
        dispatch_identifier => { is => 'String' },
        debug_mode => { is => 'Boolean', default_value => 0, is_transient => 1 },
        errors => { 
            is => 'Workflow::Operation::InstanceExecution::Error', 
            is_many => 1, 
            reverse_id_by => 'execution'
        }
    ]
};

sub _resolve_subclass_name {
    my $class = shift;

    my $store;
    if (ref($_[0]) and $_[0]->isa(__PACKAGE__)) {
        $store = $_[0]->operation_instance->store;
    } elsif (my $id = $class->get_rule_for_params(@_)->specified_value_for_property_name('instance_id')) {
        $store = Workflow::Operation::Instance->get($id)->store;
    } else {
        die 'dont know how to subclass';
    }

    my $suffix;
    foreach my $prefix ('Workflow::Store::Db','Workflow') {
        if ($class =~ /^($prefix)::(.+)$/) {
            $suffix = $2;
            last;
        }
    }
    
    return $store->class_prefix . '::' . $suffix;
}

1;
