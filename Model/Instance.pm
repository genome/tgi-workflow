
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
            id_by => 'input_connector_id'
        },
        output_connector => {
            is    => 'Workflow::Operation::Instance',
            id_by => 'output_connector_id'
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

    my @all_opi;
    foreach ( $self->operation->operations ) {
        my $this_data = Workflow::Operation::Instance->create(
            operation       => $_,
            parent_instance => $self
        );
        $this_data->input(  {} );
        $this_data->output( {} );
        push @all_opi, $this_data;
    }
    foreach (@all_opi) {
        $_->set_input_links;
    }

    $self->input_connector(
        Workflow::Operation::Instance->get(
            operation       => $self->operation->get_input_connector,
            parent_instance => $self
        )
    );

    $self->output_connector(
        Workflow::Operation::Instance->get(
            operation       => $self->operation->get_output_connector,
            parent_instance => $self
        )
    );

    return $self;
}

sub incomplete_operation_instances {
    my $self = shift;

    my @all_data = $self->child_instances;

    return grep { !$_->is_done } @all_data;
}

sub resume {
    my $self = shift;
    die 'tried to resume a finished operation: ' . $self->id
      if ( $self->is_done );

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

    $self->current->start_time( UR::Time->now );
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

    $self->current->end_time( UR::Time->now );
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
      grep { $_->is_ready && !$_->is_done && !$_->is_running } @_;

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
