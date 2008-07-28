package Workflow::Test::Command::WidgetReader;

use strict;
use warnings;

use Workflow;
use Command; 


class Workflow::Test::Command::WidgetReader {
    is => ['Workflow::Test::Command'],
    has => [
        size => { is_optional => 1 },
        color => { is_optional => 1 },
        shape => { is_optional => 1 },
        widget => { },
    ],
};

operation_io Workflow::Test::Command::WidgetReader {
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
