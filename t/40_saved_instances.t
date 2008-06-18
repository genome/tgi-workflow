#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;
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

    my $s;
#    my $s = $data->save_instance;
#    ok($s,'saved operation instance');

    $s = $set->save_instance;
    ok($s,'saved model instance');

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

#my ($saved) = Workflow::Operation::SavedInstance->get();
#my $normal = $saved->load_instance($w);

#print Data::Dumper->new([$saved, $normal])->Dump;

