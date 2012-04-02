
use strict;
use warnings;

use Cord;
use Cord::Simple;

package Cord::Operation::Command;

class Cord::Operation::Command {
    is => ['Command'],
    subclass_description_preprocessor => '_add_properties',
    has => [
        _operation => {
            is => 'Cord::Operation',
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

    my $optional_inputs = $operation->operation_type->optional_input_properties;
    my $inputs = [grep { my $v = $_; !grep { $v eq $_ } @$optional_inputs } @{ $operation->operation_type->input_properties}];
    my $outputs = $operation->operation_type->output_properties;
    
    my $has = {
        (map { 
            $_ => { is_input => 1, doc => 'Input' }
        } @{ $inputs }),
        (map {
            $_ => { is_input => 1, is_optional => 1, doc => 'Optional Input' }
        } @{ $optional_inputs }),
        (map {
            my $prop = $_;
            my $prop_hash = {
                is_output => 1,
                is_optional => 1,
                doc => 'Output'
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
        my %new1 = $class->__meta__->_normalize_property_description1($property_name, $old_property, $desc);
        my %new = $class->__meta__->_normalize_property_description2(\%new1, $desc);
        $desc->{has}->{$property_name} = \%new;
    }
    
    return $desc;
}

sub input_property_names {
    my $self = shift;
    my $class_meta = $self->__meta__;
    
    my @props = map { 
        $_->property_name
    } grep {
        defined $_->{'is_input'} && $_->{'is_input'}
    } $class_meta->get_all_property_metas();
    
    return @props;
}

sub output_property_names {
    my $self = shift;
    my $class_meta = $self->__meta__;
    
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
    
    my $result = Cord::Simple::run_workflow_lsf(
        $self->_operation,
        %stuff
    );

    my $result_output_returned = 0;
    if (defined $result) {
        while (my ($k,$v) = each(%$result)) {
            $self->$k($v);
            $result_output_returned = 1 if $k eq 'result';
        }
    } else {
        foreach my $error (@Cord::Simple::ERROR) {
            $self->error_message($error->error);
        }
        die 'Errors occured while executing "' . $self->_operation->name . "\"\n";
    }
    
    my $v = $self->post_execute;

    return $result_output_returned ? $v : 1;
}

1;
