
package Workflow::Operation::Instance;

use strict;
use warnings;
use Workflow ();

class Workflow::Operation::Instance {
    is_transactional => 0,
    has => [
        operation => { is => 'Workflow::Operation', id_by => 'workflow_operation_id' },
        parent_instance => { is => 'Workflow::Model::Instance', id_by => 'parent_instance_id' },
        output => { is => 'HASH' },
        input => { is => 'HASH' },
        store => { is => 'Workflow::Store' },
        output_cb => { is => 'CODE' },
        is_done => { is => 'Boolean' },
        is_running => { is => 'Boolean' },
        parallel_index => { is => 'Integer' },
        peer_of => { is => 'Workflow::Operation::Instance', id_by => 'peer_instance_id' },
        parallel_by => { is => 'String' },
        is_parallel => { 
            is => 'Boolean',
            calculate => q{
                if (defined $self->parallel_by && 
                    (ref($self->input_value($self->parallel_by)) eq 'ARRAY' || defined $self->parallel_index)) {
                    return 1;
                }
                return 0;
            },
        }
    ]
};

sub create {
    my $class = shift;
    my %args = (@_);
    my $self;
    
    my $load = $args{load_mode};
    if ($class eq __PACKAGE__ && $args{operation} && $args{operation}->isa('Workflow::Model')) {
        $self = Workflow::Model::Instance->create(%args);
        delete $args{load_mode};
    } else {
        delete $args{load_mode};
        $self = $class->SUPER::create(%args);
    }
    
    $self->parallel_by($self->operation->parallel_by)
        if (!$load && $self->operation->parallel_by);
        
    return $self;
}

sub save_instance {
    return Workflow::Operation::SavedInstance->create_from_instance(@_);
}

sub sync {
    my ($self) = @_;
    
    return;
    
    my $store;
    my $walkon = $self;
    do {
        $store = $walkon->store;
        
        unless ($store) {
            $walkon = $walkon->parent_instance;
        }
    } while (!$store);
    
    $DB::single=1;
    
    return $store->sync($self);
}

sub set_input_links {
    my $self = shift;

    my @links = Workflow::Link->get(
        right_operation => $self->operation,
    );

    my %linkage = ();
    
    foreach my $link (@links) {
        my ($opi) = $self->parent_instance->child_instances(
            operation => $link->left_operation
        );
        next unless $opi;
        
        my $linki = Workflow::Link::Instance->create(
            operation_instance => $opi,
            property => $link->left_property
        );
        
        $linkage{ $link->right_property } = $linki;
    }
    
    $self->input({
        %{ $self->input },
        %linkage
    }); 
}

sub is_ready {
    my $self = shift;

    my @required_inputs = @{ $self->operation->operation_type->input_properties };
    my %current_inputs = ();
    if ( defined $self->input ) {
        %current_inputs = %{ $self->input };
    }

    my @unfinished_inputs = ();
    foreach my $input_name (@required_inputs) {
        if (exists $current_inputs{$input_name} && 
            defined $current_inputs{$input_name} ||
            ($self->operation->operation_type->can('default_input') && 
            exists $self->operation->operation_type->default_input->{$input_name})) {
            if (UNIVERSAL::isa($current_inputs{$input_name},'Workflow::Link::Instance')) {
                unless ($current_inputs{$input_name}->operation_instance->is_done && defined $self->input_value($input_name)) {
                    push @unfinished_inputs, $input_name;
                }
            }
        } else {
            push @unfinished_inputs, $input_name;
        }
    }

    if (scalar @unfinished_inputs == 0) {
        return 1;
    } else {
        return 0;
    }
}

sub input_raw_value {
    input_value(@_[0,1],'raw_value');
}

sub input_value {
    my ($self, $input_name, $method) = @_;
    
    $method ||= 'value';
    
    return undef unless $self->input->{$input_name};
#    return $self->input->{$input_name}->value;
    
    if (UNIVERSAL::isa($self->input->{$input_name},'Workflow::Link::Instance')) {
        return $self->input->{$input_name}->value;
    } else {
        return $self->input->{$input_name};
    }
}

sub treeview_debug {
    my $self = shift;
    my $indent = shift || 0;
    
    print((' ' x $indent) . $self->operation->name . '=' . $self->id);
    if ($self->is_parallel) {
        print ' -' . $self->parallel_index;
    }
    print "\n";

    while (my ($k,$v) = each(%{ $self->input })) {
        my $vals = ref($v) eq 'ARRAY' ? $v : [$v];
        foreach $v (@$vals) {        
            if (UNIVERSAL::isa($v,'Workflow::Link::Instance')) {
                $v = $v->operation_instance->id . '->' . $v->property . (defined $v->index() ? ':' . $v->index() : '');
            }    
            print ((' ' x $indent) . ' +' . $k . '=' . $v . "\n");
        }
    }
    while (my ($k,$v) = each(%{ $self->output })) {
        my $vals = ref($v) eq 'ARRAY' ? $v : [$v];
        foreach $v (@$vals) {        
            if (UNIVERSAL::isa($v,'Workflow::Link::Instance')) {
                $v = $v->operation_instance->id . '->' . $v->property . (defined $v->index() ? ':' . $v->index() : '');
            }    
            print ((' ' x $indent) . ' -' . $k . '=' . $v . "\n");
        }
    }

    if ($self->can('child_instances')) {
        my $i = 0;
        my %ops = map { 
            $_->name() => $i++
        } $self->operation->operations_in_series();
        foreach my $child (sort { $ops{ $a->operation->name } <=> $ops{ $b->operation->name } || $a->parallel_index <=> $b->parallel_index } $self->child_instances) {
            $child->treeview_debug($indent+1);
        }
    }
}

sub execute {
    my $self = shift;

    if ($self->is_parallel && !defined $self->parallel_index) {
        $self->create_peers;
        $self->sync;
        
        foreach my $peer ($self, $self->peers) {
            $peer->execute_single;
        }
    } else {
        $self->execute_single;
    }
}

sub execute_single {
    my $self = shift;

    if ($self->parent_instance && $self == $self->parent_instance->input_connector) {
        $self->output($self->parent_instance->input);
    }
    
    my %current_inputs = ();
    foreach my $input_name (keys %{ $self->input }) {
        if (UNIVERSAL::isa($self->input->{$input_name},'Workflow::Link::Instance')) {
            $current_inputs{$input_name} = $self->input_value($input_name);
        } elsif (ref($self->input->{$input_name}) eq 'ARRAY') {
            my @new = map {
                UNIVERSAL::isa($_,'Workflow::Link::Instance') ?
                    $_->value : $_
            } @{ $self->input->{$input_name} };
            $current_inputs{$input_name} = \@new;
        }
    }

    my $executor = $self->operation->executor || $self->operation->workflow_model->executor;
    my $operation_type = $self->operation->operation_type;
    if ($operation_type->can('executor') && defined $operation_type->executor) {
        $executor = $operation_type->executor;
    }

    $executor->execute(
        operation_instance => $self,
        edited_input => \%current_inputs
    );
}

sub completion {
    my $self = shift;

    $self->is_done(1);
    $self->is_running(0);
    $self->sync;

    if ($self->parent_instance) {
        my $parent = $self->parent_instance;
        my @incomplete_operations = $parent->incomplete_operation_instances;
        if (@incomplete_operations) {
            my @runq = $parent->runq_filter($self->dependent_operations);

            foreach my $this_data (@runq) {
                $this_data->is_running(1);
            }

            foreach my $this_data (@runq) {
                $this_data->execute;
            }        
        } else {
            $parent->completion;
        }
    } elsif ($self->incomplete_peers == 0) {
        if (defined $self->peer_of && $self->peer_of != $self && defined $self->peer_of->output_cb) {
            ## this code shouldn't be messing up the primary peer instance but 
            # other changes are required to get around this, downside of the refactor
            my $return = $self->peer_of;

            while (my ($k,$v) = each(%{ $return->input })) {
                $return->input->{$k} = [$v];
            }
            while (my ($k,$v) = each(%{ $return->output })) {
                $return->output->{$k} = [$v];
            }
            
            for (my $i = 1; $i <= $self->peers; $i++) {
                my $peer = Workflow::Operation::Instance->get(
                    peer_of => $return,
                    parallel_index => $i
                );
                
                while (my ($k,$v) = each(%{ $peer->input })) {
                    $return->input->{$k}->[$i] = $v;
                }
                while (my ($k,$v) = each(%{ $peer->output })) {
                    $return->output->{$k}->[$i] = $v;
                }
            }

            $self->peer_of->output_cb->($return);
        } elsif (defined $self->output_cb) {
            $self->output_cb->($self);
        }
    }
}

sub dependent_operations {
    my ($self) = @_;

    return map {
        my ($this_data) = Workflow::Operation::Instance->get(
            operation => $_,
            parent_instance => $self->parent_instance
        );
        $this_data
    } $self->operation->dependent_operations;
}

sub depended_on_by {
    my ($self) = @_;
    
    return map {
        my ($this_data) = Workflow::Operation::Instance->get(
            operation => $_,
            parent_instance => $self->parent_instance
        );
        $this_data
    } $self->operation->depended_on_by;
}

sub create_peers {
    my $self = shift;
    my @peers = ();

    $self->parallel_index(0);
#    $self->fix_parallel_input_links;
    my @deps = $self->dependent_operations;
    foreach my $dep (@deps) {
        my %input = ();
        while (my ($k,$v) = each(%{ $dep->input })) {
            $input{$k} = [$v];
        }
        $dep->input(\%input);
    }
    
    $self->peer_of($self);
    for (my $i = 1; $i < scalar @{ $self->input_raw_value($self->parallel_by) }; $i++) {
        my $peer = Workflow::Operation::Instance->create(
            operation => $self->operation,
            parallel_index => $i,
            store => $self->store,
            peer_of => $self
        );
        $peer->parent_instance($self->parent_instance) if ($self->parent_instance);
        $peer->input($self->input);
        $peer->output({});
        $peer->fix_parallel_input_links;
        
        foreach my $dep (@deps) {
            my @k = grep {
                if (UNIVERSAL::isa($dep->input->{$_}->[0],'Workflow::Link::Instance') &&
                    $dep->input->{$_}->[0]->operation_instance == $self) {
                    1;
                } else {
                    0;
                }
            } keys %{ $dep->input };

            while (my ($k,$v) = each(%{ $dep->input })) {
                $dep->input->{$k}->[$i] = $dep->input->{$k}->[0];
            }
            foreach my $k (@k) {
                $dep->input->{$k}->[$i] = Workflow::Link::Instance->create(
                    operation_instance => $peer,
                    property => $dep->input->{$k}->[0]->property
                );
            }
        }
        
        push @peers, $peer;
    }
    $self->fix_parallel_input_links;


}

sub fix_parallel_input_links {
    my $self = shift;
    my %input = %{ $self->input };
    
    while (my ($k,$v) = each(%{ $self->input })) {
        $input{$k} = $v;
        if ($k eq $self->parallel_by) {
            if (UNIVERSAL::isa($v,'Workflow::Link::Instance')) {
                $input{$k} = $v->clone(index => $self->parallel_index);
            } else {
                $input{$k} = $input{$k}->[$self->parallel_index];
            }
        }
    }
    $self->input(\%input);
}

sub peers {
    my $self = shift;
    
    return () unless $self->peer_of;
    
    return grep {
        $_ != $self && defined $_->parallel_index
    } Workflow::Operation::Instance->get(
        operation => $self->operation,
        peer_of => $self->peer_of
    );
}

sub incomplete_peers {
    my $self = shift;
    
    return grep {
        !$_->is_done
    } $self->peers;
}

1;
