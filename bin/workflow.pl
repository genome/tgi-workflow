#!/gsc/bin/perl

use strict;
use warnings;

use above "Workflow::Command";

Workflow::Command->execute_with_shell_params_and_exit();

####################
#     ATTENTION
####################
#
# If you're seeing this message in the debugger, and 
# you launched your workflow with:
#
#   workflow ns start --debug=foo
#
# Simply hit the "Run" button to continue on toward the 
# top of your command class.  This breakpoint is set 
# automatically.
# 

=pod

=head1 NAME

genome

=head1 SYNOPSIS

workflow --help 

=head1 DESCRIPTION

This is the top-level tool for developers using workflows.

Just run it with no parameters to get a list of available commands.

Every command and sub-command supports the --help option.

=head1 OPTIONS

These depend on the specific sub-command.

=head1 DEVELOPER NOTE

Running this WITHIN a source tree that contains a Workflow namespace will automatically "use lib" your tree.

=head1 BUGS

Report bugs to apipe@genome.wustl.edu

=head1 AUTHOR

Eric Clark

eclark@genome.wustl.edu

=cut

