#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 8;

BEGIN {
    $ENV{'WF_DISPATCHER'}='fork';
}
use above 'Cord';

use_ok('Cord::Server::Remote');


$SIG{'ALRM'} = sub { ok(0,'Test took too long'); exit(1); };
alarm(30);

my ( $r, $g ) = Cord::Server::Remote->launch();

my($ur_srv_handle, $ur_guard, $hub_srv_handle, $hub_guard) = @$g;

isa_ok( $r, 'Cord::Server::Remote' );
BAIL_OUT('cannot continue tests without connection') unless defined $r;

my $sleep_op = Cord::Operation->create(
    name           => 'sleeper',
    operation_type =>
      Cord::OperationType::Command->get('Cord::Test::Command::Sleep')
);


my $xml = $sleep_op->save_to_xml();
my $response = $r->simple_start($xml,{seconds => 2});

ok($response, "Got a response back from simple_start");
is($response->[1]->{'result'}, 2, 'Result code was 2');  # Returns the number of seconds it slept
is(scalar(@$response),3, 'No errors');  # NOTE: Errors, if any, make this list 4 elements long

ok($r->quit, 'Quit remote server');

ok($hub_srv_handle->finish,'Hub Server finished');
ok($ur_srv_handle->finish,'UR Server finished');
alarm(0);
