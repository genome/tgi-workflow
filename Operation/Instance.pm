
package Workflow::Operation::Instance;

use strict;
use warnings;
use Workflow ();

class Workflow::Operation::Instance {
    id_by => [
        instance_id => { }
    ],
    has => [
        operation => {
            is => 'Workflow::Operation',
            id_by => 'workflow_operation_id',
            is_transient => 1
        },
        parent_instance => {
            is => 'Workflow::Model::Instance',
            id_by => 'parent_instance_id'
        },
        output => { is => 'HASH' },
        input => { is => 'HASH' },
        store => {
            is => 'Workflow::Store',
            id_by => 'workflow_store_id',
            is_transient => 1
        },
        output_cb => {
            is => 'CODE',
            is_transient => 1,
        },
        error_cb => {
            is => 'CODE',
            is_transient => 1,
        },
        parallel_index => { is => 'Integer' },
        peer_of => { 
            is => 'Workflow::Operation::Instance',
            id_by => 'peer_instance_id',
            is_optional => 1
        },
        parallel_by => {
            via => 'operation'
        },
        is_parallel => {
            is => 'Boolean',
            calculate => q{
                if (defined $self->parallel_by && 
                    (ref($self->input_value($self->parallel_by)) eq 'ARRAY' || defined $self->parallel_index)) {
                    return 1;
                }
                return 0;
            },
        },
        current => { 
            is => 'Workflow::Operation::InstanceExecution',
            id_by => 'current_execution_id', 
            is_optional => 1
        },
        is_done => {
            via => 'current',
            is_mutable => 1
        },
        is_running => {
            via => 'current',
            is_mutable => 1
        },
        status => {
            via => 'current',
            is_mutable => 1
        },
        debug_mode => { 
            via => 'current',
            is_mutable => 1
        }
    ]
};

sub operation_instance_class_name {
    'Workflow::Operation::Instance'
}

sub model_instance_class_name {
    'Workflow::Model::Instance'
}

sub instance_execution_class_name {
    'Workflow::Operation::InstanceExecution'
}

sub create {
    my $class = shift;
    my %args = (@_);
    my $self;
    
    my $load = $args{load_mode};

    if ($class->can('name') && $args{operation}) {
        $args{name} = $args{operation}->name;
    }
    if ($class eq $class->operation_instance_class_name && $args{operation} && $args{operation}->isa('Workflow::Model')) {
        my $model_instance_class = $class->model_instance_class_name;

        $self = $model_instance_class->create(%args);
        delete $args{load_mode};
    } else {
        delete $args{load_mode};
        $self = $class->UR::Object::create(%args);

    
#    $self->parallel_by($self->operation->parallel_by)
#        if (!$load && $self->operation->parallel_by);

        my $instance_exec_class = $class->instance_execution_class_name;

        my $ie = $instance_exec_class->create(
            operation_instance => $self,
            status => 'new',
            is_done => 0,
            is_running => 0
        );

        $self->current($ie);

    }
    
    return $self;
}

sub save_instance {
    Carp::carp('deprecated');
#    return Workflow::Operation::SavedInstance->create_from_instance(@_);
}

sub sync {
    my ($self) = @_;

    return $self->store->sync($self) if $self->store;
}

sub set_input_links {
    my $self = shift;

    my @links = Workflow::Link->get(
        right_operation => $self->operation,
    );

    my %linkage = ();
    
    foreach my $link (@links) {
        my $opi;
        foreach my $child ($self->parent_instance->child_instances) {
            if ($child->operation == $link->left_operation) {
                $opi = $child;
                last;
            }
        }
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

#    $DB::single=1 if $self->name eq 'outer cat seq feature';

    return 0 if ($self->status eq 'crashed');

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
            
            my $vallist;
            if (ref($current_inputs{$input_name}) eq 'ARRAY') {
                $vallist = $current_inputs{$input_name};
            } else {
                $vallist = [$current_inputs{$input_name}];
            }
            VALCHECK: foreach my $v (@$vallist) {
                if (UNIVERSAL::isa($v,'Workflow::Link::Instance')) {
                    if ($v->operation_instance->incomplete_peers) {
                        push @unfinished_inputs, $input_name;
                        last VALCHECK;
                    } else {
                        unless ($v->operation_instance->is_done && defined $self->input_value($input_name)) {
                            push @unfinished_inputs, $input_name;
                            last VALCHECK;
                        }
                    }
                } elsif (!defined $v) {
                    push @unfinished_inputs, $input_name;
                    last VALCHECK;
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
    print((' ' x $indent) . ' %' . join(' ',$self->status,$self->is_running,$self->is_done) . "\n");

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

sub reset_current {
    my ($self) = @_;
    
    if ($self->status eq 'crashed' or $self->status eq 'running') {
        my $instance_exec_class = $self->instance_execution_class_name;
        my $ie = $instance_exec_class->create(
            operation_instance => $self,
            status => 'new',
            is_done => 0,
            is_running => 0
        );

        $self->current($ie);    
        $self->debug_mode(1);
    }
}

sub resume {
    my ($self) = @_;
    
#    die 'nf';
    $self->reset_current;

    $self->execute;
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
        $self->sync;
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

    my $executor = $self->executor;

    print "s: " . $self->id . ' ' . $self->name . "\n";

    $executor->execute(
        operation_instance => $self,
        edited_input => \%current_inputs
    );
}

sub executor {
    my $self = shift;
    
    my $executor = $self->operation->executor || $self->operation->workflow_model->executor;
    my $operation_type = $self->operation->operation_type;
    if ($operation_type->can('executor') && defined $operation_type->executor) {
        $executor = $operation_type->executor;
    }

    return $executor;
}

our %retry_count = ();

sub completion {
    my $self = shift;

    print "e: " . $self->id . ' ' . $self->name . "\n";

    $self->is_done(1) unless $self->status eq 'crashed';
    $self->is_running(0);
    $self->sync;

    my $try_again = 0;
    if ($try_again && $self->current->status eq 'crashed') {
        die 'incomp';
        
        my $new_try = Workflow::Operation::InstanceExecution->create(
            operation_instance => $self,
            status => 'new',
            is_done => 0,
            is_running => 0
        );        
        $self->current($new_try);
        $self->is_running(1);
        
        $self->execute_single();
    } elsif ($self->parent_instance) {
        my $parent = $self->parent_instance;
        if ($self->current->status eq 'crashed') {
        
            $retry_count{$self->id} ||= 0;
            
            if (!$self->can('child_instances') && $retry_count{$self->id} < 2) {
                $retry_count{$self->id}++;
                $self->resume;
            } else {
                $parent->current->status('crashed');
                $parent->completion;
            }
        } else {
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
        } elsif ($self->current->status eq 'crashed') {
            ## crashed with no parent
            if (defined $self->error_cb) {
                $self->error_cb->($self);
            } else {
                $self->executor->exception($self,'operation died in eval block');
            }
        } elsif (defined $self->output_cb) {
            $self->output_cb->($self);
        }
    }
    $self->sync;
}

sub dependent_operations {
    my ($self) = @_;

    my @ops = $self->operation->dependent_operations;

    return map {
        $self->parent_instance->child_instances(
            workflow_operation_id => $_->id
        )
    } @ops;
}

sub depended_on_by {
    my ($self) = @_;
    
    my @ops = $self->operation->depended_on_by;
    
    return map {
        $self->parent_instance->child_instances(
            workflow_operation_id => $_->id
        )
    } @ops;
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
            if (UNIVERSAL::isa($v,'Workflow::Link::Instance') && $v->operation_instance == $self) {
                $input{$k} = [$v];
            } else {
                $input{$k} = $v;
            }
        }
        $dep->input(\%input);
    }
    my $operation_class_name = $self->operation_instance_class_name;
    
    $self->peer_of($self);
    for (my $i = 1; $i < scalar @{ $self->input_raw_value($self->parallel_by) }; $i++) {
        my $peer = $operation_class_name->create(
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
                if (ref($dep->input->{$_}) eq 'ARRAY' && 
                    UNIVERSAL::isa($dep->input->{$_}->[0],'Workflow::Link::Instance') &&
                    $dep->input->{$_}->[0]->operation_instance == $self) {
                    1;
                } else {
                    0;
                }
            } keys %{ $dep->input };

#            while (my ($k,$v) = each(%{ $dep->input })) {
#                $dep->input->{$k}->[$i] = $dep->input->{$k}->[0];
#            }
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

sub sorted_peers {
    my $self = shift;
    
    return sort {
        $a->parallel_index <=> $b->parallel_index
    } $self->peers;
}

sub incomplete_peers {
    my $self = shift;
    
    return grep {
        !$_->is_done
    } $self->peers;
}

1;
