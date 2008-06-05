# The diff command delegates to sub-commands under the adjoining directory.

package Workflow::Command::Create;

use warnings;
use strict;
use Workflow;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'Workflow::Command',
);

sub help_brief { "" }

sub shell_args_description { "[operation|...]"; }

1;
