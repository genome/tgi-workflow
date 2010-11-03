
use strict;
use warnings;
#TODO rewrite this so its a real test.
use Test::More skip_all => 1;

use IPC::Run qw(start);
use Data::Dumper;
use Storable qw/store_fd fd_retrieve/;

my $run = {
    type => 'Cord::OperationType::Dummy',
    input => { }
};

my $wtr = IO::Handle->new;
my $rdr = IO::Handle->new;

$wtr->autoflush(1);
$rdr->autoflush(1);

my @cmd = qw(workflow ns internal exec /dev/fd/3 /dev/fd/4);

my $h = start \@cmd,
    '3<pipe' => $wtr,
    '4>pipe' => $rdr;


store_fd($run, $wtr) or die "cant store to subprocess";

$h->pump;
my $out = fd_retrieve($rdr) or die "cant retrieve from subprocess";

$h->pump;


unless ($h->finish) {
    $? = $h->full_result;
    print "$?\n";

    if ($? == -1) {
        print "failed to execute $!\n";
    } elsif ($? & 127) {
        printf "child died with signal %d, %s coredump\n",
            ($? & 127), ($? & 128) ? 'with' : 'without';
    } else {
        printf "child exited with value %d\n", $? >>8;
    }
}

print Data::Dumper::Dumper($out);


