
package Workflow::Operation::Instance;

use strict;
use warnings;
use Workflow ();

class Workflow::Operation::Instance {
    sub_classification_method_name => '_resolve_subclass_name',
    id_by => [
        instance_id => { }
    ],
    has => [
        operation => { # Allow subclasses to make this optional
            is => 'Workflow::Operation',
            id_by => 'workflow_operation_id',
            is_transient => 1
        },
        operation_type => { # Required but could possibly be redefined to stand alone
            via => 'operation'
        },
        name => {
            via => 'operation'
        },
        parent_instance => {
            is => 'Workflow::Model::Instance',
            id_by => 'parent_instance_id',
            is_optional => 1
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
            is_optional => 1 
        },
        error_cb => {
            is => 'CODE',
            is_transient => 1,
            is_optional => 1 
        },
        parallel_index => { is => 'Integer', is_optional => 1 },
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
        },
        executor => { #TODO store executor upon creation
            is => 'Workflow::Executor',
            calculate => q{
                my $executor = $self->operation->executor || $self->parent_instance->executor;
                
                if ($self->operation_type->stay_in_process) {
                    $executor = Workflow::Executor::Serial->get;
                }
                return $executor;
            },
        }
    ]
};

sub _resolve_subclass_name {
    my $class = shift;

    my $store;
    if (ref($_[0]) and $_[0]->isa(__PACKAGE__)) {
        $store = $_[0]->store;
    } elsif (my $id = $class->get_rule_for_params(@_)->specified_value_for_property_name('workflow_store_id')) {
        $store = Workflow::Store->get($id);
    } else {
        die 'dont know how to subclass';
    }

    if (!$store) {
        if ($class =~ /^(.*?)::(Operation|Model)::Instance$/) {
            my $store_class_prefix = $1;
            
            $store = Workflow::Store->get(class_prefix => $store_class_prefix);
        } else {
            die 'Can\'t parse class name';
        }
    }

    my $suffix;
    foreach my $prefix ('Workflow::Store::Db','Workflow') {
        if ($class =~ /^($prefix)::(.+)$/) {
            $suffix = $2;
            last;
        }
    }
    if (ref($_[0]) && $_[0]->isa(__PACKAGE__)) {
    
        $_[0]->load_operation if ($_[0]->can('load_operation'));
    
        if ($_[0]->operation && $_[0]->operation->class eq 'Workflow::Model') {
            $suffix = 'Model::Instance';
        } else {
#            warn "unscalable old code.  should not be reached.  fix it";
#            my $opiclass = $store->class_prefix . '::Operation::Instance';

#            my @children = $opiclass->get(parent_instance_id => $_[0]->id, '-recurse' => ['parent_instance_id','instance_id']);
#            if (scalar @children > 0) {
#                $suffix = 'Model::Instance';
#            }
        }
    } elsif (my $id = $class->get_rule_for_params(@_)->specified_value_for_property_name('workflow_operation_id')) {
        my $operation = Workflow::Operation->get($id);
        if ($operation->class eq 'Workflow::Model') {
            $suffix = 'Model::Instance';
        }
    } else {
        die 'dont know how to subclass';
    }

    return $store->class_prefix . '::' . $suffix;
}

our @observers = (
    Workflow::Operation::InstanceExecution->add_observer(
        aspect => 'status',
        callback => sub {
            my ($self,$property,$old,$new) = @_;

            if ($old eq 'done' && $new ne $old) {
                $self->operation_instance->_undo_done_instance($old,$new);
            }
        }
    )
);

sub _undo_done_instance {
    my ($self, $old, $new) = @_;
    # This is fired by the above observer when status goes from 'done' 
    # to anything.  It's expected that the property has already been 
    # set, this is not meant to do it itself.
    
    $self->is_done(0);
    if ($self->can('input_connector')) {
        # Going from done to new on a model means we have to restart
        # all our children, because some prior operation wants to rerun
        # and could change our input.
        
        # The other case where this changes would be 'done' to 'crashed'
        # In the case of a model that means partially complete.  In this
        # scenario we don't want to touch anything because someone has
        # already done that for us.
        
        # I guess its possible for client code to directly change a model
        # from new to crashed, maybe we should rerun the output connector
        # in that case?
        
        if ($new eq 'new') {
            my $instance = $self->input_connector;
            # Changing the status of our input connector will fire this
            # method again, causing it to find all dependencies inside
            # and flag them to run again.

            $instance->status('new') 
                if ($instance->status eq 'done');
        }
    }
    
    foreach my $instance ($self->dependent_operations) {
        # If one of my siblings crashed, it would rerun anyway but
        # when its a model it wouldn't restart completely.  We have
        # to explicitly set it to done here, so it fires back into
        # this method when the state flips from done to new.

        $instance->status('done')
            if $instance->status('crashed');

        # Flag everything that depends on me to rerun.  These
        # are siblings in the current model.  It will fire this
        # method again and continue to check deps down the tree.
        
        $instance->status('new') 
            if ($instance->status eq 'done');
    }
    
    if ($self->name eq 'output connector' && $self->parent_instance->status eq 'done') {    
        # Being an output connector with my parent's status as done
        # I have to set my parent to crashed.  If this were a full clean
        # restart of my parent, it would have already been set to new
        # by one of the above calls, or the client code.
    
        $self->parent_instance->status('crashed');
    }

}

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);

    unless ($self->current) {
        # due to the weird inheritance here, this may have already been set
        my $ie = Workflow::Operation::InstanceExecution->create(
            operation_instance => $self,
            status => 'new',
            is_done => 0,
            is_running => 0
        );

        $self->current($ie);
    }

    return $self;
}

sub sync {
    my ($self) = @_;

    return $self->store->sync($self) if $self->store;
}

sub serialize_input {
    1;
}

sub serialize_output {
    1;
}

#FIXME remove use of operation here, at first glance looks problematic anyway
# this is only called during a model constructor, its _probably_ ok
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

    return 0 if ($self->status eq 'crashed');

    my @required_inputs = @{ $self->operation_type->input_properties };
    my %current_inputs = ();
    if ( defined $self->input ) {
        %current_inputs = %{ $self->input };
    }

    my @unfinished_inputs = ();
    foreach my $input_name (@required_inputs) {
        if (exists $current_inputs{$input_name} && 
            defined $current_inputs{$input_name} ||
            ($self->operation_type->can('default_input') && 
            exists $self->operation_type->default_input->{$input_name})) {
            
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
    
    print((' ' x $indent) . $self->name . '=' . $self->id);
    if ($self->is_parallel) {
        print ' -' . $self->parallel_index;
    }
    print "\n";
    print((' ' x $indent) . ' %' . join(' ',$self->status,$self->is_running,$self->is_done) . "\n");

    while (my ($k,$v) = each(%{ $self->input })) {
        my $vals = ref($v) eq 'ARRAY' ? $v : [$v];
        foreach my $dv (@$vals) {
            my $vc = $dv;
            if (UNIVERSAL::isa($dv,'Workflow::Link::Instance')) {
                $vc = $dv->operation_instance->id . '->' . $dv->property . (defined $dv->index() ? ':' . $dv->index() : '');
            }    
            print ((' ' x $indent) . ' +' . $k . '=' . (defined $vc ? $vc : '(undef)') . "\n");
        }
    }
    while (my ($k,$v) = each(%{ $self->output })) {
        my $vals = ref($v) eq 'ARRAY' ? $v : [$v];
        foreach my $dv (@$vals) {
            my $vc = $dv;
            if (UNIVERSAL::isa($dv,'Workflow::Link::Instance')) {
                $vc = $dv->operation_instance->id . '->' . $dv->property . (defined $dv->index() ? ':' . $dv->index() : '');
            }    
            print ((' ' x $indent) . ' -' . $k . '=' . (defined $vc ? $vc : '(undef)') . "\n");
        }
    }

    if ($self->can('child_instances')) {
        my $i = 0;
        my %ops = map { 
            $_->name() => $i++
        } $self->operation->operations_in_series();  #TODO: use sorted_child_instances in Model::Instance?
        foreach my $child (sort { $ops{ $a->name } <=> $ops{ $b->name } || $a->parallel_index <=> $b->parallel_index } $self->child_instances) {
            $child->treeview_debug($indent+1);
        }
    }
}

sub reset_current {
    my ($self) = @_;
    
    if ($self->status eq 'crashed' or $self->status eq 'running') {
        my $ie = Workflow::Operation::InstanceExecution->create(
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
    
    $self->reset_current;
    $self->execute;
}

sub execute {
    my $self = shift;

    if ($self->is_parallel && !defined $self->parallel_index) {
        $self->create_peers;
        $self->sync;
        
        foreach my $peer ($self->peers) {
            $peer->is_running(1);
        }
        
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

    $executor->execute(
        operation_instance => $self,
        edited_input => \%current_inputs
    );
}

our %retry_count = ();

sub completion {
    my $self = shift;

    $self->is_done(1) unless $self->status eq 'crashed';
    $self->is_running(0);
    $self->sync;

    if ($self->parent_instance) {
        my $parent = $self->parent_instance;
        if ($self->current->status eq 'crashed') {
        
            $retry_count{$self->id} ||= 0;
            
            if (!$self->can('child_instances') && $retry_count{$self->id} < 2) {
                $retry_count{$self->id}++;
                $self->resume;
            } else {
                my @running_siblings = grep { $_->is_running } ($parent->child_instances);
                unless (@running_siblings) {
                    # when there are siblings of mine running, i will assume they will call completion on my parent
                    $parent->completion;
                }
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

                my @running = grep { $_->is_running } ($parent->child_instances);
                if (scalar @runq == 0 && scalar @running == 0) {
                    # nothing running and nothing able to run next
                    
                    $parent->completion;
                }
            } else {
                $parent->completion;
            }
        }
    } elsif ($self->is_parallel && $self->unreturned_peers == 0) {
        my $mp = $self->peer_of;

        my $crashcnt = 0;
        foreach my $p ($mp, $mp->peers) {
            $crashcnt++ if $p->status eq 'crashed';
        }

        if ($crashcnt > 0) {
            if (defined $mp->error_cb) {
                $mp->error_cb->($mp);
            } else {
                $mp->executor->exception($self,'operation died in eval block');
            }
        } else {
            my $mp = $self->peer_of;

            while (my ($k,$v) = each(%{ $mp->input })) {
                $mp->input->{$k} = [$v];
            }
            while (my ($k,$v) = each(%{ $mp->output })) {
                $mp->output->{$k} = [$v];
            }
            
            for (my $i = 1; $i <= $self->peers; $i++) {
                my $peer = Workflow::Operation::Instance->get(
                    peer_of => $mp,
                    parallel_index => $i
                );
                
                while (my ($k,$v) = each(%{ $peer->input })) {
                    $mp->input->{$k}->[$i] = $v;
                }
                while (my ($k,$v) = each(%{ $peer->output })) {
                    $mp->output->{$k}->[$i] = $v;
                }
            }

            ### need some way to make sure the signal fires when input and output get changed here

            $mp->serialize_input;
            $mp->serialize_output;

            if (defined $mp->output_cb) {
                $mp->output_cb->($mp);
            }
        
        }
    } elsif (!$self->is_parallel) {
        if ($self->status eq 'crashed') {
            if (defined $self->error_cb) {
                $self->error_cb->($self);
            } else {
                $self->executor->exception($self,'operation died in eval block');
            }
        } else {
            if (defined $self->output_cb) {
                $self->output_cb->($self);
            }
        }
    }
    $self->sync;
}

# FIXME: the next two methods might be misnamed

sub dependent_operations {
    my ($self) = @_;

    my %instances = ();
    return () unless $self->parent_instance;

    foreach my $sibling ($self->parent_instance->child_instances) {
        next if $sibling == $self;
        
        foreach my $v (values %{ $sibling->input }) {
            if (UNIVERSAL::isa($v,'Workflow::Link::Instance')) {
                $instances{ $sibling->id } = $sibling
                    if ($v->operation_instance == $self);
            } elsif ($self->is_parallel && ref($v) eq 'ARRAY') {
                my $vv = $v->[$self->parallel_index];
                if (UNIVERSAL::isa($vv,'Workflow::Link::Instance')) {
                    $instances{ $sibling->id } = $sibling
                        if ($vv->operation_instance == $self);
                }
            }
        }
    }
        
    return values %instances;
}

sub depended_on_by {
    my ($self) = @_;

    my %instances = ();
    foreach my $v (values %{ $self->input }) {
        if (UNIVERSAL::isa($v,'Workflow::Link::Instance')) {
            $instances{ $v->operation_instance->id } = $v->operation_instance;
        } elsif (ref($v) eq 'ARRAY') {
            foreach my $vv (@$v) {
                if(UNIVERSAL::isa($v,'Workflow::Link::Instance')) {
                    $instances{ $vv->operation_instance->id } = $vv->operation_instance;
                }
            }
        }        
    }
    
    return values %instances;
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
        
        $peer->is_running($self->is_running);
        $peer->current->status($self->status);
        $peer->current->start_time(UR::Time->now);
        
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
    $self->peer_of($self);
    $self->fix_parallel_input_links;

    foreach my $dep (@deps) {
        $dep->serialize_input;
    }
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
        operation => $self->operation,  #TODO shouldnt be needed, verify and remove
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

sub unreturned_peers {
    my $self = shift;
    
    return grep {
        $_->status ne 'crashed' && !$_->is_done
    } $self->peers;
}

# advanced magic
sub get_by_path {
    my ($self, $path) = @_;

    my @tokens = split(/\//,$path);
    my $first = shift @tokens;
    my $rest = join('/',@tokens);
    
    my @all_instances = ();
    
    my @converted = $self->_convert_token($first);
    my @instances;
    if (ref($self)) {
        @instances = $self->child_instances(@converted);
    } else {
        @instances = $self->get(@converted);
    }

    if ($rest ne '') {
        foreach my $instance (@instances) {
            push @all_instances, $instance->get_by_path($rest);
        }
    } else {
        push @all_instances, @instances;
    }
    
    return @all_instances;
}

sub _convert_token {
    my ($self, $token) = @_;
    
    if ($token =~ /^\*/) {
        my $name = substr($token,1);
        
        return (name => $name);
    } else {
        return $token;
    }
}

1;
