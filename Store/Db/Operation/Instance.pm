
package Workflow::Store::Db::Operation::Instance;

use strict;
use warnings;
use Storable qw(freeze thaw);
use Workflow ();

class Workflow::Store::Db::Operation::Instance {
    is => ['Workflow::Operation::Instance'],
    sub_classification_method_name => '_resolve_subclass_name',
    type_name => 'instance',
    table_name => 'INSTANCE',
    id_by => [
        instance_id => { is => 'INTEGER' },
    ],
    has => [
        cache_workflow       => { 
            is => 'Workflow::Store::Db::Cache',
            id_by => 'cache_workflow_id',
            is_optional => 1 
        },
        cache_workflow_id    => { is => 'INTEGER', is_optional => 1 },
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

sub operation_instance_class_name {
    'Workflow::Store::Db::Operation::Instance'
}

sub model_instance_class_name {
    'Workflow::Store::Db::Model::Instance'
}

sub instance_execution_class_name {
    'Workflow::Store::Db::Operation::InstanceExecution'
}

sub _resolve_subclass_name {
    my ($class, $self) = @_;

    if (ref($self) && UNIVERSAL::isa($self,'Workflow::Operation::Instance')) {
        my @children = Workflow::Store::Db::Operation::Instance->get(
            parent_instance_id => $self->id
        );

        if (@children > 0) {
            return 'Workflow::Store::Db::Model::Instance';
        }
    }

    return $class;
}

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);

    if (!defined $self->cache_workflow_id && 
        !defined $self->parent_instance && 
        !defined $self->peer_of) {
        my $c = Workflow::Store::Db::Cache->create(
            xml => $self->operation->save_to_xml
        );

        $self->cache_workflow($c);
    }
    
    return $self;
}

our @OBSERVERS = (
    __PACKAGE__->add_observer(
        aspect => 'load',
        callback => sub {
            my ($self) = @_;
            
#            print "loading " . $self->name . " " . $self->id . "\n";
            
            if ($self->cache_workflow) {
                my $op = Workflow::Model->create_from_xml($self->cache_workflow->xml);

                $self->operation($op);
            } elsif ($self->parent_instance) {
                my $parent = $self->parent_instance;
                
                my ($op) = $parent->operation->operations(
                    name => $self->name
                );
                
                $self->operation($op) if $op;
                print "not yet\n" unless $op;
            }
            
            if (!$self->parent_instance) {
                my $store = Workflow::Store::Db->create;
                $self->store($store);
            }
            
            $self->input(thaw $self->input_stored);
            $self->output(thaw $self->output_stored);
            
            # find any child instances and set their op
            
            if ($self->can('child_instances') && $self->operation) {
                foreach my $i ($self->child_instances) {
                    $i->store($self->store);
                    my ($op) = $self->operation->operations(
                        name => $i->name
                    );
                    
                    $i->operation($op);
                    
                    if ($i->name eq 'input connector') {
                        $self->input_connector($i);
                    }
                    if ($i->name eq 'output connector') {
                        $self->output_connector($i);
                    }
                }
                
            }
        }
    ),
    __PACKAGE__->add_observer(
        aspect => 'input',
        callback => sub {
            my ($self) = @_;

            return if !defined $self->input;

            local $Storable::forgive_me = 1;
            $self->input_stored(freeze $self->input);
        }
    ),    
    __PACKAGE__->add_observer(
        aspect => 'output',
        callback => sub {
            my ($self) = @_;

            return if !defined $self->output;

            local $Storable::forgive_me = 1;
            $self->output_stored(freeze $self->output);
        }
    )
);

1;
