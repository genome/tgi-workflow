
use strict;
use warnings;

use Workflow;
use YAML;

package Workflow::Command::Resume;

class Workflow::Command::Resume {
    is => ['Workflow::Command'],
    has => [
        instance_id => {
            is => 'Number',
            doc => 'The unique ID of the workflow root instance to resume'
        },
        namespace => { 
            is => 'String',
            is_optional => 1,
            doc => 'namespace to use, ex: Genome',
        },
#        debug => {
#            is => 'Boolean',
#            is_optional => 1,
#            doc => 'Open the perl tk debugger to the crashed operation'
#        }
    ]
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Show";
}

sub help_synopsis {
    return <<"EOS"
    workflow resume  
EOS
}

sub help_detail {
    return <<"EOS"
Resume a workflow serially in one process for debugging purposes.
EOS
}

sub execute {
    my $self = shift;

    eval "use " . $self->namespace;
    # i dont care what the result is, so we're not checking $@ 
    
    my @i = Workflow::Store::Db::Operation::Instance->get(
        id => $self->instance_id,
        -recurse => ['parent_instance_id','instance_id']
    );

    my $i = Workflow::Operation::Instance->get($self->instance_id);

    $i->operation->set_all_executor(Workflow::Executor::SerialDeferred->get);

    $i->is_running(1);
    $i->resume;

    $i->operation->wait;

}

1;
