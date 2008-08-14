#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 8;
use Devel::Size qw(size total_size);
use Workflow;

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


my ($saved) = Workflow::Operation::SavedInstance->get(82);
my $normal = $saved->load_instance($w);
my @opi = $normal->child_instances;

ok($saved, 'got saved model');
ok($normal, 'loaded saved model');
ok(@opi, 'saved model has operation instances');

#print Data::Dumper->new([$saved, $normal,\@opi],['saved','normal','operation_instances'])->Dump;

#$normal->treeview_debug;
