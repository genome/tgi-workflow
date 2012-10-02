
package Workflow::Model::Instance;

use strict;
use warnings;

class Workflow::Model::Instance {
    isa => 'Workflow::Operation::Instance',
    has => [
        child_instances => {
            is            => 'Workflow::Operation::Instance',
            is_many       => 1,
            reverse_id_by => 'parent_instance'
        },
        input_connector => {
            is    => 'Workflow::Operation::Instance',
            via => 'child_instances',
            to => '-filter',
            where => ['name' => 'input connector'],
        },
        output_connector => {
            is    => 'Workflow::Operation::Instance',
            via => 'child_instances',
            to => '-filter',
            where => ['name' => 'output connector'],
        },
        ordered_child_instances => {
            is        => 'Workflow::Operation::Instance',
            is_many   => 1,
            calculate => q{ $self->sorted_child_instances }
        },
    ]
};


## TODO rewrite so it doesnt lean on operation->operations_in_series
sub sorted_child_instances {
    my $self = shift;

    my $i = 0;
    my %ops =
    map { $_->name() => $i++ } $self->operation->operations_in_series();

    my @child = sort {
        $ops{ $a->name } <=> $ops{ $b->name }
        || $a->name cmp $b->name
        || $a->parallel_index <=> $b->parallel_index
    } $self->child_instances(@_);

    return @child;
}

# This function can lean on the plan objects for more information.
sub create {
    my $class = shift;
    my %args  = (@_);
    my $self  = $class->SUPER::create(%args);

    # create a child opi for each child op
    my @child_opis;
    my @child_op_ids;
    my %child_opi_id_by_op_id;
    for my $child_op ( $self->operation->operations ) {
        my $child_opi = Workflow::Operation::Instance->create(
            operation       => $child_op,
            parent_instance => $self
        );
        #$child_opi->input(  {} );
        $child_opi->output( {} );

        push @child_opis, $child_opi;
        push @child_op_ids, $child_op->id;
        $child_opi_id_by_op_id{$child_op->id} = $child_opi->id;
    }
    
    # make one pass through all of the links and index them by "right" (to) operation 
    my @all_links = Workflow::Link->get( right_workflow_operation_id => \@child_op_ids);
    my %links_by_right_op;
    for my $link (@all_links) {
        my $a = $links_by_right_op{$link->right_workflow_operation_id} ||= [];
        push @$a, $link;
    }

    #warn "starting profiling at " . time() . " in file " . __FILE__ . " on line " . __LINE__ . "\n";
    #DB::enable_profile();
    
    # Make one link instance per link. 
    # Go through all of the links which go "to" a given node at once
    # so we only have to reset its input hash one time.
    for my $right_opi (@child_opis) {
        my $right_op_id = shift @child_op_ids;
        my $links_to_right_op = $links_by_right_op{$right_op_id} || [];

        my %added_inputs = ();
        foreach my $link (@$links_to_right_op) {
            my $left_op_id = $link->left_workflow_operation_id;
            my $left_opi_id = $child_opi_id_by_op_id{$left_op_id};
            next unless $left_opi_id;

            my $linki = Workflow::Link::Instance->create(
                other_operation_instance_id => $left_opi_id,
                property           => $link->left_property
            );

            $added_inputs{ $link->right_property } = $linki;
        }
        $right_opi->input( \%added_inputs );
    }
    
    #warn "stop profiling at " . time() . " in file " . __FILE__ . " on line " . __LINE__ . "\n";
    #exit;  # disable profiling and exit so the file is written

    return $self;
}

sub incomplete_operation_instances {
    my $self = shift;

    my @all_data = $self->child_instances;

    return grep { !$_->is_done } @all_data;
}

sub resume {
    my $self = shift;

    if($self->is_done) {
        die 'tried to resume a finished operation: ' . $self->id
    }

    $self->input_connector->output( $self->input );

    foreach my $child ( $self->child_instances ) {
        $child->reset_current;
    }

    $self->current->status('running');
    $self->is_running(1);

    my @runq = $self->runq();

    foreach my $this_data (@runq) {
        $this_data->is_running(1);
    }

    foreach my $this_data (@runq) {
        $this_data->resume;
    }

    return $self;
}

sub execute {
    my $self = shift;

    $self->current->start_time( Workflow::Time->now );
    $self->current->status('running');
    $self->is_running(1);

    $self->input_connector->output( $self->input );
    $self->SUPER::execute;
}

sub execute_single {
    my $self = shift;

    my @runq = $self->runq;
    foreach my $this_data (@runq) {
        $this_data->is_running(1);
    }

    foreach my $this_data (@runq) {
        $this_data->execute;
    }
}

sub explain {
    my $self = shift;

    my $reason = '';
    foreach my $child ( $self->child_instances ) {
        $reason .=
        $child->name . ' <' . $child->id . '> (' . $child->status . ")\n";
        if ( $child->status eq 'new' ) {
            foreach my $input ( $child->unfinished_inputs ) {
                $reason .= '  ' . $input . "\n";
            }
        }
    }

    return $reason; 
}

sub completion {
    my $self = shift;

    if ( $self->incomplete_operation_instances ) {
        $self->current->status('crashed');

        # since we're throwing an error, lets generate something useful

        my $reason =
        "Execution halted due to unresolvable dependencies or crashed children.  Status and incomplete inputs:\n" . $self->explain;

        Workflow::Operation::InstanceExecution::Error->create(
            execution => $self->current,
            error     => $reason
        );
    }

    my $oc         = $self->output_connector;
    my %newoutputs = ();
    foreach my $output_name ( keys %{ $oc->input } ) {
        if ( ref( $oc->input->{$output_name} ) eq 'ARRAY' ) {
            my @new = map {
                UNIVERSAL::isa( $_, 'Workflow::Link::Instance' )
                ? $_->value
                : $_
            } @{ $oc->input->{$output_name} };
            $newoutputs{$output_name} = \@new;
        } else {
            $newoutputs{$output_name} = $oc->input_value($output_name);
        }
    }
    $self->output( \%newoutputs );

    $self->current->end_time( Workflow::Time->now );
    $self->current->status('done') if ( $oc->current->status eq 'done' );

    $self->SUPER::completion;
}

sub runq {
    my $self = shift;

    return $self->runq_filter( $self->child_instances );
}

sub runq_filter {
    my $self = shift;

    my @runq =
    sort { $a->name cmp $b->name }
    grep { !$_->is_done && !$_->is_running && $_->is_ready } @_;

    return @runq;
}

sub delete {
    my $self = shift;

    my @all_data = $self->child_instances;
    foreach (@all_data) {
        $_->delete;
    }

    return $self->SUPER::delete;
}

1;
