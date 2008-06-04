#!/gsc/bin/perl

use strict;
use lib '/gscuser/eclark/poe_install/lib/perl5/site_perl/5.8.7';
use above 'Workflow';
use Workflow::Client;

Workflow::Client->run_worker();


