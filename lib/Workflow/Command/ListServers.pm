
package Workflow::Command::ListServers;

class Workflow::Command::ListServers {
    is => ['UR::Object::Command::List'],
    has_constant => [
        subject_class_name => {
            value => 'Workflow::Service'
        },
    ],
    has => [
        show => {
            default_value => 'hostname,port,username,process_id,start_time'
        }
    ]
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "List Servers that are running anywhere in the Genome Center";
}

sub help_synopsis {
    return <<"EOS"
    workflow list-servers 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for diagnostic purposes.
EOS
}

1;
