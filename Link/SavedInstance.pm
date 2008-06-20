
package Workflow::Link::SavedInstance;

use strict;
use warnings;

sub create {
    my $class = shift;
    my %args = @_;
    
    $args{operation_name} ||= '';
    $args{property} ||= '';
    
    my $str = $args{operation_name} . ':' . $args{property};
    
    bless \$str, $class;
}

sub operation_name {
    my $self = shift;
    
    if (my $value = shift) {
        my ($curr_op, $curr_prop) = split(':',$$self);
        
        $$self = $value . ':' . $curr_prop;
    }
    
    return (split(':',$$self))[0];
}

sub property {
    my $self = shift;
    
    if (my $value = shift) {
        my ($curr_op, $curr_prop) = split(':',$$self);
        
        $$self = $curr_op . ':' . $value;
    }

    return (split(':',$$self))[1]; 
}

sub create_from_instance {
    my ($class, $unsaved) = @_;

    my $self = $class->create;
    
    $self->operation_name($unsaved->operation_instance->operation->name);
    $self->property($unsaved->property);
    
    return $self;
}

sub load_instance {
    my $self = shift;
    my $model_instance_unsaved = shift;
    
    my $found;
    foreach my $opi ($model_instance_unsaved->operation_instances) {
        if ($opi->operation->name eq $self->operation_name) {
            $found = $opi;
            last;
        }
    }
    
    if (!defined $found) {
        return undef;
    }
    
    my $unsaved = Workflow::Link::Instance->create();
    $unsaved->operation_instance($found);
    $unsaved->property($self->property);
    
    return $unsaved;
}

1;
