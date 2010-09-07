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

my $child1 = fork;
if ($child1) {
    my $child2 = fork;
    if ($child2) {
        close OUT_R;
        close ERR_R;

        waitpid($pid, 0);
        my $exit = $?;

        waitpid($child2, 0);
        waitpid($child1, 0);

        exit $exit;
    } elsif (defined $child2) {
        close OUT_R;

        prefixlines(\*ERR_R,\*STDERR,$hostname);

        exit;
    } else {
        die "can't fork: $!";
    }
} elsif (defined $child1) {
    close ERR_R;

    prefixlines(\*OUT_R,\*STDOUT,$hostname);

    exit;
} else {
    die "can't fork: $!";
}

## never reached.
