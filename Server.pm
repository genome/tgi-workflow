
package Workflow::Server;

use strict;
#use POE;
#use POE qw(Component::IKC::Server);

our $lockdir = '/tmp';

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
=pod
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
=cut
}

sub lock {
    my ($class,$service) = @_;
    
    $class->wait_for_lock($service);

    my $lockname = $lockdir . '/.workflow-' . $service;
    
    my $f = IO::File->new('>' . $lockname);
    $f->print($$);
    $f->close;
}

sub unlock {
    my ($class,$service) = @_;
    
    my $lockname = $lockdir . '/.workflow-' . $service;

    unlink($lockname);
}

sub wait_for_lock {
    my ($class,$service) = @_;
    
    my $lockname = $lockdir . '/.workflow-' . $service;

    my $waited = 0;
    while (-e $lockname) {
        die 'exceeded lock time' if ($waited > 300);
        sleep 5;
        $waited += 5;
#        print "$service wait: $waited\n";
    }
}

1;
