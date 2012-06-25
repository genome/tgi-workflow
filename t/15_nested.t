#!/usr/bin/env perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT}=1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS}=1;
}

use strict;
use warnings;

use Test::More tests => 6;
use above 'Workflow';

my $dir = -d 't/xml.d' ? 't/xml.d' : 'xml.d';

require_ok('Workflow::Model');
can_ok('Workflow::Model',qw/create validate is_valid execute/);

my $w = Workflow::Model->create_from_xml($dir . '/10_nested.xml');
ok($w,'create workflow');
isa_ok($w,'Workflow::Model');

ok(do {
    $w->validate;
    $w->is_valid;
},'validate');

$w->parallel_by('model input string');

$DB::single = 1;
my $data = $w->execute(
    input => {
        'test input' => [
            qw/ab cd ef gh jk/
        ]
    }
);
$w->wait;

my $output = $data->output;
is_deeply(
    $output,
    {
        'test output' => [qw/ab cd ef gh jk/],
        'result' => [1,1,1,1,1]
    },
    'check output'
);
