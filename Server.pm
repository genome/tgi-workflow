
package Workflow::Server;

use strict;
use POE;

sub setup {
    my $class = shift;
    die "$class didn't implement setup method!"; 
}

sub start {
    my $class = shift;
    
    $class->setup(@_);
    POE::Kernel->run();
}

sub check_leaks {
    my($kernel)=@_[KERNEL];
    if(ref $kernel) {
        my $kr_queue = $kernel->[5];

        warn(
    "\n<rc> ,----- Kernel Activity -----\n",
      "<rc> | Events : ", $kr_queue->get_item_count(), "\n",
      "<rc> | Files  : ", $kernel->_data_handle_count(), "\n",
      "<rc> | Extra  : ", $kernel->_data_extref_count(), "\n",
      "<rc> | Procs  : ", $kernel->_data_sig_child_procs(), "\n",
      "<rc> `---------------------------\n",
      "<rc> ..."
        );
$kernel->_dump_kr_extra_refs;
    } else {
        warn "$kernel isn't a reference";
    }
}

1;
