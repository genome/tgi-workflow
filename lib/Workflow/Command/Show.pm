
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
            shell_args_position => 1,
            doc => 'The unique ID of the Instance to show'
        },
        debug => {
            is => 'Boolean',
            is_optional => 1,
            doc => 'Show a tree of all underlying operations with debug flags'
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
    
    my $i = Workflow::Operation::Instance->get($self->instance_id);

    if ($self->debug) {
        $i->treeview_debug;
    } else {

        {
            no warnings;
            print <<MARK;
Id:          @{[$i->id]}
Parent Id:   @{[$i->parent_instance_id]}
Name:        @{[$i->name]}
Status:      @{[$i->status]}
Start Time:  @{[$i->current->start_time]}
End Time:    @{[$i->current->end_time]}
Dispatch Id: @{[$i->current->dispatch_identifier]}
Cache Id:    @{[$i->cache_workflow_id]}
Username:    @{[$i->current->user_name]}
Stdout Log:  @{[$i->current->stdout]}
Stderr Log:  @{[$i->current->stderr]}
CPU Time:    @{[$i->current->cpu_time]}
Max Memory:  @{[$i->current->max_memory]}
Max Swap:    @{[$i->current->max_swap]}
Input:
@{[ YAML::Dump($i->input) ]}
Output:
@{[ YAML::Dump($i->output) ]} 
MARK
        }

        if ($i->can('sorted_child_instances')) {
            print sprintf("%9s %-60s %9s\n%80s\n",qw/id name status/,('-'x 80));
            $self->_print_child($i,0);
        }
    }
}

sub _print_child {
    my $self = shift;
    my $i = shift;
    my $d = shift;
    
    print sprintf("%9s %-60s %9s\n",$i->id, (' 'x$d) . $i->name, $i->status);
    if ($i->can('sorted_child_instances')) {
        foreach my $c ($i->sorted_child_instances) {
            $self->_print_child($c,$d+1);
        }
    }
}

1;
