
package Workflow::Cache::View::Plan::Xml;

class Workflow::Cache::View::Plan::Xml {
    is => 'UR::Object::View::Default::Text',
    has_constant => [
        perspective => {
            value => 'plan'
        },
        toolkit => {
            value => 'png'
        }
    ]
};

sub _generate_content {
    my $self = shift;

    return $self->subject->plan->save_to_xml;
}

1;
