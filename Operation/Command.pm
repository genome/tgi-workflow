
use strict;
use warnings;

use Workflow;
use Workflow::Simple;

package Workflow::Operation::Command;

class Workflow::Operation::Command {
    is => ['Command'],
    subclass_description_preprocessor => '_add_properties',
    has => [
        _operation => {
            is => 'Workflow::Operation',
            id_by => 'workflow_operation_id'
        },
        workflow_operation_id => {
            is_constant => 1
        }
    ]
};

sub _add_properties {
    my $class = shift;
    my $desc = shift;
    
    unless (exists $desc->{'extra'}->{'workflow'}) {
        die 'workflow not defined in class definition';
    }
    
    my $operation_code = delete $desc->{'extra'}->{'workflow'};
    my $operation = $operation_code->();

    my @errors = $operation->validate;
    if (@errors) {
        warn join("\n", @errors);
    } 

    my $inputs = $operation->operation_type->input_properties;
    my $outputs = $operation->operation_type->output_properties;
    
    my $has = {
        (map { 
            $_ => { is_input => 1 }
        } @{ $inputs }),
        (map {
            my $prop = $_;
            my $prop_hash = {
                is_output => 1,
                is_optional => 1,
            };
            
            if (grep { $prop eq $_ } @{ $inputs }) {
                # bidirectional
                $prop_hash->{is_input} = 1;
            }
            
            $prop => $prop_hash;
        } grep { $_ ne 'result' } @{ $outputs }),
        workflow_operation_id => {
            is_param => 1,
            is_constant => 1,
            is_class_wide => 1,
            value => $operation->id
        }
    };
    
    while (my ($property_name, $old_property) = each(%$has)) {
        my %new = $class->get_class_object->_normalize_property_description($property_name, $old_property, $desc);
        $desc->{has}->{$property_name} = \%new;
    }
    
    return $desc;
}

sub input_property_names {
    my $self = shift;
    my $class_meta = $self->get_class_object;
    
    my @props = map { 
        $_->property_name
    } grep {
        defined $_->{'is_input'} && $_->{'is_input'}
    } $class_meta->get_all_property_metas();
    
    return @props;
}

sub output_property_names {
    my $self = shift;
    my $class_meta = $self->get_class_object;
    
    my @props = map { 
        $_->property_name
    } grep {
        defined $_->{'is_output'} && $_->{'is_output'}
    } $class_meta->get_all_property_metas();
    
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
        $self->_operation,
        %stuff
    );

    if (defined $result) {
        while (my ($k,$v) = each(%$result)) {
            $self->$k($v);
        }
    } else {
        foreach my $error (@Workflow::Simple::ERROR) {
            $self->error_message($error->error);
        }
        die 'too many errors';
    }
    
    return $self->post_execute;
}

1;
