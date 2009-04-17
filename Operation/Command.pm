
use strict;
use warnings;

use Workflow;
use Workflow::Simple;

package Workflow::Operation::Command;

class Workflow::Operation::Command {
    is => ['Workflow::Command'],
    has => [
        operation => {
            is => 'Workflow::Operation',
            id_by => 'workflow_operation_id'
        },
        workflow_operation_id => {
            is_constant => 1
        }
    ]
};

sub input_property_names {
    my $class = ref($_[0]) || $_[0];
    
    my $class_meta = $class->get_class_object;
    
    my @props = map { 
        $_->property_name
    } grep {
        defined $_->{'is_input'} && $_->{'is_input'}
    } $class_meta->get_all_property_objects();
    
    return @props;
}

sub output_property_names {
    my $class = ref($_[0]) || $_[0];
    
    my $class_meta = $class->get_class_object;
    
    my @props = map { 
        $_->property_name
    } grep {
        defined $_->{'is_output'} && $_->{'is_output'}
    } $class_meta->get_all_property_objects();
    
    return @props;
}

## instance_methods
sub pre_execute {

}

sub post_execute {
    my $self = shift;

    foreach my $n ($self->output_property_names) {
        print "$n\t" . $self->$n . "\n";
    }
    
    return $self->result;
}

sub execute {
    my $self = shift;

    $self->pre_execute;
    
    my %stuff = map {
        $_ => $self->$_
    } $self->input_property_names;
    
    my $result = Workflow::Simple::run_workflow_lsf(
        $self->operation,
        %stuff
    );

    if (defined $result) {
        while (my ($k,$v) = each(%$result)) {
            $self->$k($v);
        }
    }
    
    return $self->post_execute;
}

1;
