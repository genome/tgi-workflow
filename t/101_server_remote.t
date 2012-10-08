#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 6;

BEGIN {
    $ENV{'WF_DISPATCHER'}='fork';
}
use above 'Workflow';

use_ok('Workflow::Server::Remote');


$SIG{'ALRM'} = sub { ok(0,'Test took too long'); exit(1); };
alarm(30);

my ($r, $p, $g) = Workflow::Server::Remote->launch();

isa_ok( $r, 'Workflow::Server::Remote' );
BAIL_OUT('cannot continue tests without connection') unless defined $r;

my $sleep_op = Workflow::Operation->create(
    name           => 'sleeper',
    operation_type =>
      Workflow::OperationType::Command->get('Workflow::Test::Command::Sleep')
);


my $xml = $sleep_op->save_to_xml();
my $response = $r->start($xml,{seconds => 2});

ok($response, "Got a response back from simple_start");
is($response->[1]->{'result'}, 2, 'Result code was 2');  # Returns the number of seconds it slept
is(scalar(@$response),3, 'No errors');  # NOTE: Errors, if any, make this list 4 elements long

ok($r->end_child_servers($p, $g), 'Quit remote server');

alarm(0);
