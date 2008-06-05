#!/gsc/bin/perl

use strict;
use lib '/gscuser/eclark/poe_install/lib/perl5/site_perl/5.8.7';
use above 'Workflow';

use Workflow::Server;

my $server = Workflow::Server->create;

POE::Kernel->run();


