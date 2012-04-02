#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 4;

$ENV{UR_DBI_NO_COMMIT} = 1;

use above 'Cord';

my $foo;

ok($foo = Cord::Service->create(port => 123),'created service record');

ok(UR::Context->commit,'commit');
ok($foo->delete,'deleted service record');
ok(UR::Context->commit,'commit');

