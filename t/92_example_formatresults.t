#!/gsc/bin/perl

use strict;
use warnings;
use Test::More;

plan tests => 4;

use_ok('Cord::Command::Example::FormatResults');

my $obj = Cord::Command::Example::FormatResults->create;

$obj->test_files([ ['abcd'], ['efgh'], ['ijkl'] ]);
$obj->test_results([ 1, 1, 0 ]);

ok( $obj, 'created command object' );

ok( defined $obj->execute, 'executed' );

is_deeply( $obj->failed_tests, ['ijkl'], 'failed tests correct' );

