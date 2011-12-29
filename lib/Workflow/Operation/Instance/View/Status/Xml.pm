package Workflow::Operation::Instance::View::Status::Xml;

our @aspects = qw/name status start_time end_time elapsed_time operation_type parallel_index is_parallel/;

push @aspects,
  {
    name               => 'current',
    subject_class_name => 'Workflow::Operation::InstanceExecution',
    perspective        => 'default',
    toolkit            => 'xml',
    aspects => []
  };

class Workflow::Operation::Instance::View::Status::Xml {
    is  => 'Workflow::Operation::Instance::View::Default::Xml',
    has => [
        default_aspects =>
          { value => [ 'cache_workflow_id', @aspects, &related_instances(0) ] },
    ]
};

#TODO clean up this ugly way to specify aspects

sub related_instances {
    return if $_[0] > 10;

    return {
        name               => 'related_instances',
        subject_class_name => 'Workflow::Operation::Instance',
        perspective        => 'default',
        toolkit            => 'xml',
        aspects => [ @aspects, &related_instances( $_[0] + 1 ) ]
    };
}

sub _generate_content {
    my $self = shift;

    #preload the child instances
    my $subject = $self->subject;
    if($subject) {
        my @all_exec_ids;
        my @children = $subject;
        while(@children) {
            my @exec_ids = map($_->current_execution_id, @children);
            push @all_exec_ids, @exec_ids;
            @children =
                (Workflow::Operation::Instance->get(parent_execution_id => \@exec_ids),
                Workflow::Operation::Instance->get(parent_instance_id => [map($_->id, @children)]));
        }
        my @x = Workflow::Operation::InstanceExecution->get(\@all_exec_ids);
    }

    return $self->SUPER::_generate_content(@_);
}

1;
