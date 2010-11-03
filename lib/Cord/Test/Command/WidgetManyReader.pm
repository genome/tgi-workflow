package Cord::Test::Command::WidgetManyReader;

use strict;
use warnings;

use Cord;
use Command; 

class Cord::Test::Command::WidgetManyReader {
    is => ['Workflow::Test::Command'],
    has_output => [
        size => { is_many => 1, is_optional => 1 },
        color => { is_many => 1, is_optional => 1 },
        shape => { is_many => 1, is_optional => 1 },
    ],
    has_input => [
        widget => { is_many => 1 },
    ],
};

sub execute {
    my $self = shift;

    my @size = ();
    my @color = ();
    my @shape = ();

    foreach my $w ($self->widget) {
        push @size, $w->size;
        push @color, $w->color;
        push @shape, $w->shape;
    }

    $self->size(\@size);
    $self->color(\@color);
    $self->shape(\@shape);

    return 1;
}
 
1;
