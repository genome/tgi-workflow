#!/usr/bin/env perl

use strict;
use warnings;
use POSIX qw(strftime uname);
use IPC::Open3 qw(open3);

sub prefixlines {
    my ($in, $out, $prefix) = @_;

    select $out;
    $| = 1;

    while (my $line = <$in>) {
        print strftime('%Y-%m-%d %H:%M:%S%z', gmtime),
            ' ', $prefix, ' ', $line;
    }
}

my $hostname = (uname)[1];
$hostname = substr($hostname,0,index($hostname,'.'));

pipe OUT_R, OUT_W;
pipe ERR_R, ERR_W;

my $pid = open3('<&STDIN', '>&OUT_W', '>&ERR_W', @ARGV);

close OUT_W;
close ERR_W;

my $child = fork;
if ($child) {
    close OUT_R;

    prefixlines(\*ERR_R,\*STDERR,$hostname);

    waitpid($pid, 0);
    my $exit = $?;
    waitpid($child, 0);

    exit $exit;
} elsif (defined $child) {
    close ERR_R;

    prefixlines(\*OUT_R,\*STDOUT,$hostname);

    exit;
} else {
    die "can't fork: $!";
}

## never reached.
