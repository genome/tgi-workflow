#!/usr/bin/env perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
}

use strict;
use warnings;

use UR;
use Test::More tests => 10;
use Devel::Size qw(size total_size);
use Workflow;

my $dir = -d 't/xml.d' ? 't/xml.d' : 'xml.d';

my $id;

require_ok('Workflow::Model');
can_ok('Workflow::Model',qw/create validate is_valid execute/);

{
    my $w = Workflow::Model->create_from_xml($dir . '/00_basic.xml');
    ok($w,'create workflow');

    ok(do {
        $w->validate;
        $w->is_valid;
    },'validate');

    my $collector = sub {
        my ($data) = @_;

        diag(ref($data) . ' ' . $data->id);

        $id = $data->id;

        # just let it leave scope
    };

    ok($w->execute(
        input => {
            'model input string' => 'abracadabra321',
            'sleep time' => 1
        },
        store => Workflow::Store::Db->create(),
        output_cb => $collector
    ),'execute');

    ok($w->wait,'wait');

    ok(UR::Context->commit,'commit');
    
    $w->delete;
}

foreach my $ds (UR::DataSource->all_objects_loaded) {
    $ds->_set_all_objects_saved_committed;
}

UR::Context->_reverse_all_changes();
UR::Context->clear_cache;

my $pass = 1;
foreach my $o (UR::Object->all_objects_loaded) {
    my @c = $o->inheritance();
    unshift @c, $o->class;
    pop @c if ($c[-1] eq 'UR::ModuleBase');
    pop @c if ($c[-1] eq 'UR::Object');
    
    unless (grep(/^UR::/, @c)) {
        diag(ref($o) . ' ' . $o->id);
        unless (ref($o) eq 'Workflow::Store::Db' or ref($o) eq 'Workflow::OperationType::Command') {
            $pass = 0;
        }
    }
}
ok($pass,'cleared workflow objects');


foreach my $o (values %$UR::DeletedRef::all_objects_deleted) {
#    print Data::Dumper->new([$o])->Dump . "\n";
    if ($o->{original_class} eq 'Workflow::OperationType::Command') {
        diag('wtf');
        $o->resurrect;
    }
}

my $normal = Workflow::Store::Db::Operation::Instance->get($id);

$DB::single=1;
$normal->treeview_debug;

