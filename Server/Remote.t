#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 20;

use above 'Workflow';

use_ok('Workflow::Server::Remote');

my $r = Workflow::Server::Remote->launch(
#    host => 'localhost',
#    port => 13425
);

isa_ok( $r, 'Workflow::Server::Remote' );
BAIL_OUT('cannot continue tests without connection') unless defined $r;
ok($r->print_STDOUT("stdout test\n"),'called stdout test');
ok($r->print_STDERR("stderr test\n"),'called stderr test');

my @test_ids = ( 28, 41, 122 );
for (@test_ids) {
    $r->_seval(
        q{
            my @load = Workflow::Store::Db::Operation::Instance->get(
                id => } . $_ . q{,
                -recurse => ['parent_instance_id','instance_id']
            );
        }
    );
}

is_deeply([$r->loaded_instances],\@test_ids,'got loaded_instances');
ok($r->quit,'told server to quit');
isa_ok( $r, 'UR::DeletedRef' );

ok(wait,'server has quit');

