package Cord::Operation::Instance::View::Status::Xml;

our @aspects = qw/name status start_time end_time elapsed_time operation_type parallel_index is_parallel/;

push @aspects,
  {
    name               => 'current',
    subject_class_name => 'Cord::Operation::InstanceExecution',
    perspective        => 'default',
    toolkit            => 'xml',
    aspects => []
  };

class Cord::Operation::Instance::View::Status::Xml {
    is  => 'Cord::Operation::Instance::View::Default::Xml',
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
        subject_class_name => 'Cord::Operation::Instance',
        perspective        => 'status',
        toolkit            => 'xml',
        aspects => [ @aspects, &related_instances( $_[0] + 1 ) ]
    };
}

1;
