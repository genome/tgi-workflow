package Workflow::Operation::SavedInstance;

use strict;
use warnings;
use Storable qw(freeze thaw);

use Workflow;
class Workflow::Operation::SavedInstance {
    type_name => 'operation saved instance',
    table_name => 'SAVED_INSTANCE',
    id_by => [
        instance_id => { is => 'INTEGER' },
    ],
    has => [
        input                 => { is => 'BLOB', is_optional => 1 },
        is_done               => { is => 'INTEGER', is_optional => 1 },
        is_parallel           => { is => 'INTEGER', is_optional => 1 },
        is_running            => { is => 'INTEGER', is_optional => 1 },
        name                  => { is => 'TEXT' },
        orig_instance_id      => { is => 'TEXT' },
        output                => { is => 'BLOB', is_optional => 1 },
        parallel_index        => { is => 'INTEGER', is_optional => 1 },
        parent_instance_id    => { is => 'INTEGER', is_optional => 1 },
        peer_of_id            => { is => 'INTEGER', is_optional => 1 },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

sub create_from_instance {
    my ($class, $unsaved, $parent_saved_instance, $stop_recurse) = @_;
    
    if ($unsaved->parent_instance && !defined $parent_saved_instance) {
        # find it
        
        $parent_saved_instance = Workflow::Operation::SavedInstance->get(
            orig_instance_id => $unsaved->parent_instance->id
        );
    }
    
    my $self = $class->get(
        orig_instance_id => $unsaved->id
    );
        
    unless ($self) {
        $self = $class->create(
            orig_instance_id => $unsaved->id
        );
    }

    $self->input(freeze $unsaved->input); #$newinput);
    $self->output(freeze $unsaved->output);
    $self->name($unsaved->operation->name);
    $self->is_done($unsaved->is_done);
    $self->is_running($unsaved->is_running);
    $self->is_parallel($unsaved->is_parallel);
    $self->parallel_index($unsaved->parallel_index);

    if ($unsaved->parent_instance) {
        $self->parent_instance_id($parent_saved_instance->id);
    }

    # parents are expected to find peer operations and save them
    # as well as set my peer_of_id

    if (!$unsaved->parent_instance && $unsaved->peer_of && !defined $stop_recurse) {
        if ($unsaved->peer_of == $unsaved) {
            foreach my $peer ($unsaved->peers) {
                my $saved = $peer->save_instance(undef,1);
                $saved->peer_of_id($self->id);
            }
        } else {
            $unsaved->peer_of->save_instance(undef,1);
        }
    }

    # find child operations and save them.
    
    if ($unsaved->can('child_instances')) {
        my @child_instances = $unsaved->child_instances;
        my @master_peers = grep {
            defined $_->peer_of && $_->peer_of == $_
        } @child_instances;
        
        my %peer_id_map = ();
        foreach my $child (@master_peers) {
            my $saved_child = $child->save_instance($self);
            $saved_child->peer_of_id($saved_child->id);
            $peer_id_map{ $child->id } = $saved_child->id;
        }
        foreach my $child (@child_instances) {
            if (!exists $peer_id_map{ $child->id }) {
                my $saved_child = $child->save_instance($self);
                if ($child->peer_of) {
                    $saved_child->peer_of_id($peer_id_map{ $child->peer_of->id });
                }   
            }
        }
    }
    
    return $self;
}

## this is here to help solve out of order loading
my $peer_queue = [];

sub load_instance {
    my $self = shift;
    my $operation = shift; ## the real Workflow::Operation, not an instance of execution
    my $parent_instance = shift;

    my $unsaved;
    if ($unsaved = Workflow::Operation::Instance->get($self->orig_instance_id)) {
        $unsaved->operation($operation);
    } else {
        $unsaved = Workflow::Operation::Instance->create(
            id => $self->orig_instance_id,
            operation => $operation,
            load_mode => 1
        );
    }

    $unsaved->parent_instance($parent_instance)
        if $parent_instance;
    
    $unsaved->is_done($self->is_done);
    $unsaved->is_running($self->is_running);
    $unsaved->parallel_index($self->parallel_index);
    $unsaved->parallel_by($operation->parallel_by);

    my $inputs = thaw $self->input;

    $unsaved->input($inputs);    
    $unsaved->output(thaw $self->output);

    if ($self->peer_of_id) {
        if ($self->peer_of_id == $self->id) {
            $unsaved->peer_of($unsaved);
        } else {
            my $ps = Workflow::Operation::SavedInstance->get($self->peer_of_id);
            unless ($ps) {
                Carp::croak('op points to a missing peer');
            }

            if (!defined $parent_instance) {
                my $unsaved_peer = $ps->load_instance($operation);
            }

            push @$peer_queue, [$unsaved, $ps->orig_instance_id];
        }
        _peer_load_queue();
    }

    my @children = Workflow::Operation::SavedInstance->get(
        parent_instance_id => $self->id
    );

    foreach my $child (@children) {
        my $child_operation = $operation->operations(name => $child->name);
        Carp::croak('missing ' . $child->name . '. wrong workflow?')
            unless $child_operation;
        my $unsaved_child = $child->load_instance($child_operation, $unsaved);
        if ($child->name eq 'input connector') {
            $unsaved->input_connector($unsaved_child);
        }
        if ($child->name eq 'output connector') {
            $unsaved->output_connector($unsaved_child);
        }
    }

    
    return $unsaved;
}

sub _peer_load_queue {
    my $new_queue = [];
    while (scalar (@$peer_queue)) {
        my ($unsaved, $peer_id) = @{ shift @$peer_queue };
        my $p = Workflow::Operation::Instance->get($peer_id);

        if ($p) {
            $unsaved->peer_of($p);
        } else {        
            push @$new_queue, [$unsaved,$peer_id];
        }
    }
    $peer_queue = $new_queue;
}

1;
