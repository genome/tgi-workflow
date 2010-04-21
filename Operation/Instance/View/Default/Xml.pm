package Workflow::Operation::Instance::View::Default::Xml;

class Workflow::Operation::Instance::View::Default::Xml {
    is => 'UR::Object::View::Default::Xml'
};

sub _resolve_default_aspects {
    my $self = shift;
    my @super = $self->SUPER::_resolve_default_aspects;
    return grep { $_ !~ /put_stored$/ } @super;
}

1;
