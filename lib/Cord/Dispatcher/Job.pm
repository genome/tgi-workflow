package Cord::Dispatcher::Job;

class Cord::Dispatcher::Job {
    has => [
        resource => { is => 'Cord::Resource' },
        command => { is => 'Text' },
        # group is e.g. /workflow-worker2 in workflow
        group => { is => 'Text', is_optional => 1 },
        name => { is => 'Text', is_optional => 1 },
        project => { is => 'Text', is_optional => 1 },
        queue => { is => 'Text', is_optional => 1 },
        stdout => { is => 'Text', is_optional => 1 },
        stderr => { is => 'Text', is_optional => 1 }
    ]
};

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = {};
    
    $struct->{resource} = $self->resource->as_xml_simple_structure;

    foreach my $key (qw/resource command group name project queue stdout stderr/) {
        $struct->{$key} = $self->$key if (defined $self->$key);
    }
    return $struct;
}

sub create_from_xml_simple_structure {
    my ($cls, $struct) = @_;

    my $resource = Cord::Resource->create_from_xml_simple_structure($struct->{resource});
    my $self = $cls->create(
        resource => $resource,
        command => $struct->{command}
    );

    foreach my $key (qw/group name project queue stdout stderr/) {
        $self->$key(delete $struct->{$key}) if (exists $struct->{$key});
    }

    return $self;
}
