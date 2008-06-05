#!/usr/bin/env perl

use strict;
use warnings;

use Test::More qw(no_plan);
use IO::Dir;
use Workflow;

my $dir = -d 't/xml.d' ? 't/xml.d' : 'xml.d';

require_ok('Workflow::Model');
can_ok('Workflow::Model',qw/create_from_xml validate is_valid/);

ok(-d $dir,'finding xml.d directory');
my @files;

my $d;
ok(do{
    $d = IO::Dir->new($dir);
    while (defined($_ = $d->read)) {
        push @files, $_ if ($_ =~ /\d{2}_.+?\.xml/);
    }
    $d;
}, 'opening dir');

ok(@files,'finding XX_yyyy.xml files');

foreach my $file (@files) {
    ok( do {
        my $w = Workflow::Model->create_from_xml($dir . '/' . $file);
        $w->validate;
        ($file =~ /_invalid/) ? !$w->is_valid : $w->is_valid;
    },'load and validate ' . $file);
}
