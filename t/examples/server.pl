#!/gsc/bin/perl

use strict;
use above 'Cord::Server::Hub';
use Cord::Server::UR;

POE::Kernel->stop();

my $pid = fork;
if ($pid) {
    print "$$ parent\n";
    Cord::Server::Hub->start;
} elsif (defined $pid) {
    print "$$ child\n";
#    Cord::Server::HTTPD->start;
    Cord::Server::UR->start;
} else {
    warn "no child?";
}

