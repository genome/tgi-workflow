package Workflow::Command::Create::Operation;

use strict;
use warnings;

use above "Workflow";
use Command; 
use YAML;

class Workflow::Command::Create::Operation {
    is => ['Workflow::Command'],
    has => [
        wrap_class => { is_optional=>0, doc=>'class name to base the operation on' },
    ],
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Create an operation with default values by inspecting a Command class";
}

sub help_synopsis {
    return <<"EOS"
    workflow-test create operation --wrap-class=Workflow::Test::Command::Sleep 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for testing purposes.
EOS
}

sub execute {
    my $self = shift;
  
    $self->status_message('Wrapping class ' . $self->wrap_class);
    my $class_to_wrap = $self->wrap_class;

    eval "use $class_to_wrap";
    if ($@) {
        $self->error_message("Cannot use $class_to_wrap\n" . $@);
        return;
    }

    $DB::single=1;
    my %seen = ();
    my @io = map {
        {
            type => $self->_probable_property_type($_),
            name => $_->property_name
        }
    } sort {
        $a->property_name cmp $b->property_name
    } grep {
        $_->property_name ne 'id' &&
        $_->property_name ne 'bare_args' &&
#        $_->property_name ne 'result' &&
        $_->property_name ne 'is_executed' &&
        $_->property_name !~ /^_/ #&&
#        !exists $seen{$_->property_name} &&
#        do { $seen{$_->property_name} = 1 }
    } map {
        $class_to_wrap->get_class_object->get_property_meta_by_name($_)
    } $class_to_wrap->get_class_object->all_property_names; 

    print YAML::Dump @io;

    1;
}

sub _probable_property_type {
    my ($self, $property_meta) = @_;

    my $type = 'Unknown';
    if ($property_meta->property_name eq 'result' ||
        $property_meta->is_calculated) {
        $type = 'Output';
    }

    return $type;
} 
1;
