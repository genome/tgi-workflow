#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 9;
use Devel::Size qw(size total_size);
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

my $collector = sub {
    my ($data, $set) = @_;

    my $s = $data->save_instance;
    ok($s,'saved operation instance');

    # just let it leave scope
};

$w->execute(
    input => {
        'model input string' => 'abracadabra321',
        'sleep time' => 1
    },
    output_cb => $collector
);

$w->wait;

$w = Workflow::Model->create_from_xml($dir . '/10_nested.xml');
ok($w,'create nested workflow');
isa_ok($w,'Workflow::Model');

ok(do {
    $w->validate;
    $w->is_valid;
},'validate');

my $data = $w->execute(
    input => {
        'test input' => [
            qw/ab cd ef gh jk/
        ]
    }
);

$data->save_instance;

#ok(UR::Context->commit,'commit');
