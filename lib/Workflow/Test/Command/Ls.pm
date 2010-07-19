package Workflow::Test::Command::Ls;

use strict;
use warnings;

use Workflow;
use Command; 

my $testdir = $ENV{WF_TESTDIR};

class Workflow::Test::Command::Ls {
    is => ['Workflow::Test::Command'],
    has_param => [
        lsf_queue => {
            default_value => 'short',
        },
        lsf_resource => {
            default_value => "-R 'rusage[mem=4000] span[hosts=1]'" . (defined $testdir ? " -o $testdir/stdout -e $testdir/stderr" : ''),
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
