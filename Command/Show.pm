
use strict;
use warnings;

use Workflow;
use YAML;

package Workflow::Command::Show;

class Workflow::Command::Show {
    is => ['Workflow::Command'],
    has => [
        instance_id => {
            is => 'Number',
            doc => 'The unique ID of the Instance to show'
        },
        debug => {
            is => 'Boolean',
            is_optional => 1,
            doc => 'Show a tree of all underlying operations for debugging'
        }
    ]
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Show";
}

sub help_synopsis {
    return <<"EOS"
    workflow show 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for diagnostic purposes.
EOS
}

sub execute {
    my $self = shift;
    
    my $i = Workflow::Store::Db::Operation::Instance->get($self->instance_id);

    if ($self->debug) {
        $i->treeview_debug;
    } else {
        print <<MARK;
Id:          @{[$i->id]}
Name:        @{[$i->name]}
Status:      @{[$i->status]}
Start Time:  @{[$i->current->start_time]}
End Time:    @{[$i->current->end_time]}
Dispatch Id: @{[$i->current->dispatch_identifier]}
Input:
@{[ YAML::Dump($i->input) ]}
Output:
@{[ YAML::Dump($i->output) ]} 
MARK

    }
}

1;
