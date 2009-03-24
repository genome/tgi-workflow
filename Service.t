#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 2;

$ENV{UR_DBI_NO_COMMIT} = 1;

use above 'Workflow';

my $foo;

ok($foo = Workflow::Service->create(port => 123),'created service record');

ok(UR::Context->commit,'commit');
ok($foo->delete,'deleted service record');
ok(UR::Context->commit,'commit');

