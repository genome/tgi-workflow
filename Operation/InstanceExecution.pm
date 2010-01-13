
package Workflow::Operation::InstanceExecution;

use strict;
use warnings;

class Workflow::Operation::InstanceExecution {
    sub_classification_method_name => '_resolve_subclass_name',
    has => [
        operation_instance => { is => 'Workflow::Operation::Instance', id_by => 'instance_id' },
        status => { is_optional => 1 },
        start_time => { is_optional => 1 },
        end_time => { is_optional => 1 },
        exit_code => { is_optional => 1 },
        stdout => { is_optional => 1 },
        stderr => { is_optional => 1 },
        is_done => { is => 'Boolean', is_optional => 1 },
        is_running => { is => 'Boolean', is_optional => 1  },
        dispatch_identifier => { is => 'String', is_optional => 1  },
        cpu_time      => { is => 'NUMBER', len => 11, is_optional => 1 },
        max_threads   => { is => 'NUMBER', len => 4, is_optional => 1 },
        max_swap      => { is => 'NUMBER', len => 6, is_optional => 1 },
        max_processes => { is => 'NUMBER', len => 4, is_optional => 1 },
        max_memory    => { is => 'NUMBER', len => 6, is_optional => 1 },
        user_name     => { is => 'String', len => 20, is_optional => 1 },
        debug_mode => { is => 'Boolean', default_value => 0, is_transient => 1, is_optional => 1 },
        errors => { 
            is => 'Workflow::Operation::InstanceExecution::Error', 
            is_many => 1, 
            reverse_id_by => 'execution',
            is_optional => 1 
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

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);

    $self->fix_logs;
    $self->user_name(scalar getpwuid $<);

    return $self;
}

sub fix_logs {
    my $self = shift;

    if (my $out = $self->operation_instance->out_log_file) {
        $self->stdout($out);
    }
    if (my $err = $self->operation_instance->err_log_file) {
        $self->stderr($err);
    }
}

1;
