package Cord::Job;

use strict;
use Cord;
use Cord::Job::Event;

class Cord::Job {
    is          => 'UR::Value',   ## necessary for UR to call _load during get()
    is_abstract => 1,
    sub_classification_method_name => '_resolve_subclass_name',
    id_by                          => [
        job_id => {
            is  => 'Number',
            doc => 'id that is locally unique to the job dispatcher'
        }
    ],
    has => [
        type => {
            is  => 'String',
            doc => 'used to resolve the subclass'
        },
    ],
    has_many => [
        events => {
            is         => 'Cord::Job::Event',
            reverse_as => 'job'
        }
    ]
};

sub _load {
    my $class = shift;
    my $rule  = shift;

    $DB::single = 1;

    my @obj = $UR::Context::current->get_objects_for_class_and_rule($class, $rule);

    unless (@obj) {
        my $subclass = $class->_resolve_subclass_name($rule->params_list);
        @obj = $subclass->_create_object($rule);
        for (@obj) { $_->__signal_change__("load"); }
    }

    return @obj;
}

sub type {
    my $self = shift;
    if (@_) {
        die 'cannot change type after creation';
    }
    if ( my $type = $self->__type ) {
        return $type;
    } else {
        return $self->__type( lc( ( split( '::', ref($self) ) )[-1] ) );
    }
}

sub _resolve_subclass_name {
    my $class = shift;
    my $subclass_name;

    $DB::single = 1;

    if ( $class ne __PACKAGE__ ) {
        $subclass_name = $class;
    } elsif ( my $type =
        $class->get_rule_for_params(@_)
        ->specified_value_for_property_name('type') )
    {
        $subclass_name = __PACKAGE__ . '::' . ucfirst( $type );
    } else {
        die 'dont know how to subclass';
    }

    $subclass_name->class if $subclass_name;
    return $subclass_name;
}

1;
