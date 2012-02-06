
package Workflow::Server;

use strict;

sub setup {
    my $class = shift;
    die "$class didn't implement setup method!";
}

sub start {
    my $class = shift;

    select STDERR; $| = 1;
    select STDOUT; $| = 1;

    # linux kernel to sends HUP if our parent process ends.
    # non-portable
    syscall 172, 1, 1;

    $class->setup(@_);
    POE::Kernel->run();
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
    my ($class,$service,$handle) = @_;

    my $lockname = $class->lockname($service);

    my $waited = 0;
    while (-e $lockname) {
        if ($waited > 300) {
            print STDERR qx(cat $lockname);
            print STDERR qx(ls -lh $lockname);
            die "exceeded lock time for $lockname";
        }
        sleep 5;
        $handle->pump_nb if (defined $handle);
        $waited += 5;
    }
}

1;
