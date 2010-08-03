
use strict;
use warnings;

use IPC::Open2;
use Data::Dumper;
use Storable qw/store_fd fd_retrieve/;

my $run = {
    type => 'abcd',
    input => 'efgh'
};


my ($rdr, $wtr);
my $pid = open2($rdr, $wtr, 'workflow ns internal exec 0 1');

store_fd($run, $wtr) or die "cant store to subprocess";
my $out = fd_retrieve($rdr) or die "cant retrieve from subprocess";

my $exit = waitpid(-1,0);

if ($? == -1) {
    print "failed to execute $!\n";
} elsif ($? & 127) {
    printf "child died with signal %d, %s coredump\n",
        ($? & 127), ($? & 128) ? 'with' : 'without';
} else {
    printf "child exited with value %d\n", $? >>8;
}

print Data::Dumper::Dumper($out);


