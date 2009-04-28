
use strict;
use warnings;

use Workflow;

package Workflow::Command::Graph;

class Workflow::Command::Graph {
    is => ['Workflow::Command'],
    has => [
        xml => {
            is => 'String',
            doc => 'XML file name to graph'
        },
        png => {
            is => 'String',
            doc => 'PNG output file to save to'
        }
    ]
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Show";
}

sub help_synopsis {
    return <<"EOS"
    workflow graph --xml example.xml --png output.png 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for diagnostic purposes.
EOS
}

sub execute {
    my $self = shift;
    
    unless (-e $self->xml) {
        $self->error_message("Can't find xml file: " . $self->xml);
        exit;
    }
    
    my $wf = Workflow::Operation->create_from_xml($self->xml);

    my @errors = $wf->validate;
    
    if (scalar @errors) {
        print "Validation failed!\n";
        foreach my $error (@errors) {
            print "$error\n";
        }
        exit;
    }

    $wf->as_png($self->png);

}

1;
