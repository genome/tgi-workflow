
package Cord::Cache::View::Graph::Png;

class Cord::Cache::View::Graph::Png {
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

    my $png = $self->subject->plan->as_png;

    return $png;
}

1;
