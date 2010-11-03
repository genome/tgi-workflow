package Cord::Test::Command::WidgetReader;

use strict;
use warnings;

use Cord;
use Command; 


class Cord::Test::Command::WidgetReader {
    is => ['Cord::Test::Command'],
    has_output => [
        size => { is_optional => 1 },
        color => { is_optional => 1 },
        shape => { is_optional => 1 },
    ],
    has => [
        widget => { is_input => 1 },
    ],
};

operation_io Cord::Test::Command::WidgetReader {
    input  => [ 'widget' ],
    output => [ 'size', 'color', 'shape' ],
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Sleeps for the specified number of seconds";
}

sub help_synopsis {
    return <<"EOS"
    workflow-test 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for testing purposes.
EOS
}

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
