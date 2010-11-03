package Workflow::Test::Command::WidgetReader;

use strict;
use warnings;

use Workflow;

class Workflow::Test::Command::WidgetReader {
    is => ['Workflow::Test::Command'],
    has_output => [
        size => { is_optional => 1 },
        color => { is_optional => 1 },
        shape => { is_optional => 1 },
    ],
    has => [
        widget => { is_input => 1 },
    ],
};

sub execute {
    my $self = shift;

    my $w = $self->widget;
    
    $self->size($w->size);
    $self->color($w->color);
    $self->shape($w->shape);

    sleep 10;
    
    return 1;
}
 
1;
