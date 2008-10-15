#!/gsc/bin/perl

use strict;
use above 'Workflow::Server::HTTPD';
use POE qw(Component::IKC::Client);

my $client = POE::Component::IKC::Client->spawn(
    ip => 'localhost',
    port => 13425,
    name => 'HTTPD',
    on_connect => sub {
        Workflow::Server::HTTPD->setup;
    }
);

POE::Kernel->run;


