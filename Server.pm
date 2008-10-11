
use strict;

package Workflow::Server;

sub setup {
    my $class = shift;
    die "$class didn't implement setup method!"; 
}

sub start {
    my $class = shift;
    
    $class->setup(@_);
    POE::Kernel->run();
}

1;
