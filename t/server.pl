#!/gsc/bin/perl

use strict;
use above 'Workflow';

use Workflow::Server;

my $server = Workflow::Server->create;

POE::Kernel->run();


