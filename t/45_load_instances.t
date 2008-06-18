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


my ($saved) = Workflow::Model::SavedInstance->get();
my $normal = $saved->load_instance($w);
my @opi = $normal->operation_instances;
my $parent = $normal->parent_instance;

ok($saved, 'got saved model');
ok($normal, 'loaded saved model');
ok(@opi, 'saved model has operation instances');
ok($parent, 'saved model has parent');

#print Data::Dumper->new([$saved, $normal, $parent, \@opi])->Dump;
