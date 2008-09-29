#!/gsc/bin/perl

use strict;
use above 'Workflow';

use Workflow::Server;
use Workflow::Server::HTTPD;

my $server = Workflow::Server->create;
my $http = Workflow::Server::HTTPD->create;

POE::Kernel->run();


