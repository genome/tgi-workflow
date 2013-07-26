package Workflow::Command::ShowXml;

use strict;
use warnings;

use Workflow;

class Workflow::Command::ShowXml {
    is => ['Workflow::Command'],
    has => [
        instance_id => {
            is => 'Number',
            shell_args_position => 1,
            doc => 'The unique ID of the Instance to show'
        },
    ],
};

sub execute {
    my $self = shift;

    my $workflow_instance = Workflow::Operation::Instance->get($self->instance_id);
    if ($workflow_instance) {
        my $xml = $workflow_instance->cache_workflow->plan->save_to_xml();
        print $xml;
    } else {
        $self->error_message("Couldn't find a workflow instance with id: " . $self->instance_id . "\n");
    }
}

sub help_brief {
    "ShowXml";
}

sub help_synopsis {
    return <<"EOS"
    workflow show xml
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for diagnostic purposes.
EOS
}

1;
