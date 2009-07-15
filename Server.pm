
package Workflow::Server;

use strict;
#use POE;
#use POE qw(Component::IKC::Server);

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

sub lockname {
    my ($class,$service) = @_;
    
    my $lock_root = '/gsc/var/lock/workflow';
    
    my $hostname = `hostname -s`;
    chomp $hostname;
    
    my $lockname = $lock_root . '/' . $hostname . '-' . $service;
    my $gid = getgrnam('gsc');
    
    if (!-e $lock_root) {
        mkdir $lock_root;
        
        chown -1, $gid, $lock_root;
        chmod oct('2775'), $lock_root;
    }
    
    return $lockname;
}

sub lock {
    my ($class,$service) = @_;
    
    $class->wait_for_lock($service);

    my $lockname = $class->lockname($service);
    
    my $f = IO::File->new('>' . $lockname);

    if (defined $f) {
        $f->print($$);
        $f->close;
    } else {
        die 'cannot open lock file for writing: ' . $lockname;
    }
}

sub unlock {
    my ($class,$service) = @_;
    
    my $lockname = $class->lockname($service);

    unlink($lockname);
}

sub wait_for_lock {
    my ($class,$service) = @_;
    
    my $lockname = $class->lockname($service);

    my $waited = 0;
    while (-e $lockname) {
        die 'exceeded lock time' if ($waited > 300);
        sleep 5;
        $waited += 5;
#        print "$service wait: $waited\n";
    }
}

1;
