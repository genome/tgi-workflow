#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;
use Workflow;

my $dir = -d 't/xml.d' ? 't/xml.d' : 'xml.d';

require_ok('Workflow::Model');
can_ok('Workflow::Model',qw/create validate is_valid execute/);

my $w = Workflow::Model->create_from_xml($dir . '/00_basic.xml');
ok($w,'create workflow');
isa_ok($w,'Workflow::Model');

ok(do {
    $w->validate;
    $w->is_valid;
},'validate');

$w->parallel_by('model input string');

my $data = $w->execute(
    input => {
        'model input string' => [
            qw/ab cd ef gh jk/
        ],
        'sleep time' => 1
    }
);

$w->wait;

my $output = $data->output;
is_deeply(
    $output,
    {
        'model output string' => [qw/ab cd ef gh jk/],
        'today' => [UR::Time->today,UR::Time->today,UR::Time->today,UR::Time->today,UR::Time->today],
        'result' => [1,1,1,1,1]
    },
    'check output'
);
