
package Workflow::Store::Db::Operation::Instance;

use strict;
use warnings;
use Storable qw(freeze thaw);

class Workflow::Store::Db::Operation::Instance {
    sub_classification_method_name => '_resolve_subclass_name',
    is => ['Workflow::Operation::Instance'],
    type_name => 'instance',
    table_name => 'WORKFLOW_INSTANCE',
    id_by => [
        instance_id => { is => 'INTEGER', column_name => 'workflow_instance_id' },
    ],
    has => [
        cache_workflow       => { 
            is => 'Workflow::Store::Db::Cache',
            id_by => 'cache_workflow_id',
            is_optional => 1 
        },
        cache_workflow_id    => { is => 'INTEGER', column_name => 'workflow_plan_id', is_optional => 1 },
        current => { 
            is => 'Workflow::Store::Db::Operation::InstanceExecution', 
            id_by => 'current_execution_id', 
            is_optional => 1
        },
        current_execution_id => { is => 'INTEGER', is_optional => 1 },
        input_stored         => { is => 'BLOB', is_optional => 1 },
        name                 => { is => 'TEXT' },
        output_stored        => { is => 'BLOB', is_optional => 1 },
        parallel_index       => { is => 'INTEGER', is_optional => 1 },
        parent_instance => {
            is => 'Workflow::Store::Db::Model::Instance',
            id_by => 'parent_instance_id'
        },
        parent_instance_id   => { is => 'INTEGER', is_optional => 1 },
        peer_of => {
            is => 'Workflow::Store::Db::Operation::Instance',
            id_by => 'peer_instance_id'
        },
        peer_instance_id     => { is => 'INTEGER', is_optional => 1 },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

sub load_operation {
    my ($self) = shift;
    
    if ($self->parent_instance_id) {
        my $parent = $self->parent_instance;
        my ($op) = $parent->operation->operations(
            name => $self->name
        );

        $self->store($parent->store);
        $self->operation($op) if $op;
#        print "not yet\n" unless $op;
    } elsif ($self->cache_workflow  && !$self->workflow_operation_id) {
        my $op = Workflow::Model->create_from_xml($self->cache_workflow->xml);

        $self->operation($op);
    } 

}

our @OBSERVERS = (
    __PACKAGE__->add_observer(
        aspect => 'load',
        callback => sub {
            my ($self) = @_;
                        
            $self->load_operation;
            
            if (!$self->parent_instance_id) {
                my $store = Workflow::Store::Db->get;
                $self->store($store);
            }
            
            $self->input(thaw $self->input_stored);
            $self->output(thaw $self->output_stored);


            if ($self->parent_instance_id && ($self->name eq 'input connector' || $self->name eq 'output connector')) {
                my $parent = $self->parent_instance;

                my $name = $self->name;
                $name =~ s/ /_/g;

                $parent->$name($self);
            }            
#            if ($self->can('child_instances') && $self->operation) {
#                if (!$self->input_connector_id || !$self->output_connector_id) {
#                    foreach my $i ($self->child_instances(name => ['input connector','output connector'])) {
#                        my $name = $i->name;
#                        next unless ($name eq 'input connector' || $name eq 'output connector');
#                        $name =~ s/ /_/g;
#                        $self->$name($i);
#                    }
#                }               
#            }
        }
    ),
    __PACKAGE__->add_observer(
        aspect => 'create', # due to weird inheritance this is better as an observer 
        callback => sub {
            my $self = shift;

            if (!defined $self->cache_workflow_id && 
                !defined $self->parent_instance && 
                !defined $self->peer_of) {
                my $c = Workflow::Store::Db::Cache->create(
                    xml => $self->operation->save_to_xml
                );

                $self->cache_workflow($c);
            } elsif (defined $self->parent_instance) {
                $self->cache_workflow($self->parent_instance->cache_workflow);
            } elsif (defined $self->peer_of) {
                $self->cache_workflow($self->peer_of->cache_workflow);
            }

            $self->name($self->operation->name);

        }
    ),
    __PACKAGE__->add_observer(
        aspect => 'input',
        callback => \&serialize_input
    ),    
    __PACKAGE__->add_observer(
        aspect => 'output',
        callback => \&serialize_output
    )
);

sub serialize_input {
    my ($self) = @_;

    return if !defined $self->input;

    local $Storable::forgive_me = 1;
    $self->input_stored(freeze $self->input);
}

sub serialize_output {
    my ($self) = @_;

    return if !defined $self->output;

    local $Storable::forgive_me = 1;
    $self->output_stored(freeze $self->output);
}



1;
