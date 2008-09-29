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
    my $w = Workflow::Model->create_from_xml($dir . '/03_die.xml');
    ok($w,'create workflow');
#    ok($w->executor->limit(2),'limit executor to 2');

    ok(do {
        $w->validate;
        $w->is_valid;
    },'validate');

    my $opi;
    ok($opi = $w->execute(
        input => {
            'model input string' => 'abracadabra321',
            'sleep time' => 1
        },
        store => Workflow::Store::Db->create()
    ),'execute');
    $id = $opi->id;

    eval { ok($w->wait,'wait'); };

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

my $normal = Workflow::Store::Db::Operation::Instance->get($id);

$normal->treeview_debug;

$normal->output_cb(sub {
    print "done\n";
});

$::DONT_DIE=1;
$normal->resume();
$normal->operation->wait;

$normal->treeview_debug;
