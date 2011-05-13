package Workflow::Job::Event;

use strict;
use Workflow;

class Workflow::Job::Event {
    is_abstract                    => 1,
    sub_classification_method_name => '_resolve_subclass_name',
    id_by                          => [
        job_id => {
            is  => 'Number',
            doc => 'id that is locally unique to the job dispatcher'
        },
        time => {
            is  => 'DateTime',
            doc => 'when the event occurred'
        }
    ],
    has => [
        job_class => { is => 'String' },
        job       => {
            is          => 'Workflow::Job',
            id_class_by => 'job_class',
            id_by       => 'job_id'
        }
    ]
};

sub _resolve_subclass_name {
    my $class = shift;
    my $subclass_name;

    $DB::single = 1;

    if ( $class ne __PACKAGE__ ) {
        $subclass_name = $class;
    } elsif ( my $job_class =
        $class->define_boolexpr(@_)
        ->value_for('job_class')
        and my $job_id =
        $class->define_boolexpr(@_)
        ->value_for('job_id') )
    {
        my $type = $job_class->get($job_id)->type;
        $subclass_name = __PACKAGE__ . '::' . ucfirst( $type );
    } else {
        die 'dont know how to subclass';
    }

    $subclass_name->class if $subclass_name;
    return $subclass_name;
}

1;
