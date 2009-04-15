
package Workflow::Store;

use strict;
use warnings;

class Workflow::Store {
    is => 'UR::Singleton',
    is_transactional => 0,
    is_abstract => 1,
    id_by => 'class_prefix',
    has => [
        class_prefix => {
            is => 'String',
            is_constant => 1,
            is_class_wide => 1,
            value => 'Workflow'
        }
    ]
};

# FIXME --dynamically detect them if possible
my @sub_classes = qw{Workflow::Store::Db Workflow::Store::None};

# singleton's dont set their default values, so we'll do it.
# stolen from UR::Object->create
sub init {
    my $self = shift;

    my $class_meta = $self->get_class_object;    
    my %default_values = ();
    for my $co ( reverse( $class_meta, $class_meta->ancestry_class_metas ) ) {
        foreach my $prop ( $co->direct_property_metas ) {
            $default_values{ $prop->property_name } = $prop->default_value if (defined $prop->default_value);
        }
    }
    
    while (my ($k,$v) = each %default_values) {
        $self->$k($v);
    }
    
    1;
}

sub _resolve_subclass_name_for_id {
    my $class = shift;
    my $id = shift;
    
    my %map = $class->class_prefix_map;
    
    return $map{$id}->class;
}

sub _resolve_id_for_subclass_name {
    my $class = shift;
    my $subclass_name = shift;
    
    my $class_meta = $subclass_name->get_class_object;
    my $id = $class_meta->property_meta_for_name('class_prefix')->default_value;

    return $id;
}

sub all_class_prefixes {
    return map { $_->class_prefix } map { $_->get } @sub_classes;
}

sub class_prefix_map {
    my $class = shift;
    
    return map { my $o = $_->get; $o->class_prefix, $o } @sub_classes;
}

1;
