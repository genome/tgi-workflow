package Workflow::Test::Command::Ls;

use strict;
use warnings;

use Workflow;
use Command; 

my $testdir = $ENV{WF_TESTDIR};
my $resource = "-R 'rusage[mem=100] span[hosts=1]'" . (defined $testdir ? " -o $testdir/stdout -e $testdir/stderr" : '');

class Workflow::Test::Command::Ls {
    is => ['Workflow::Test::Command'],
    has_param => [
        lsf_queue => {
            default_value => $ENV{WF_TEST_QUEUE},
        },
        lsf_resource => {
            default_value => $resource, 
        }
    ]
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Sleeps for the specified number of seconds";
}

sub help_synopsis {
    return <<"EOS"
    workflow-test sleep --seconds=5 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for testing purposes.
EOS
}

sub execute {
    my $self = shift;


    system('ls -l');
    

    1;
}
 
1;
