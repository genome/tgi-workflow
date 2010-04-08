#!/usr/bin/env perl

use strict;
use warnings;

use Test::More qw(no_plan);
use IO::Dir;
use above 'Workflow';

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

foreach my $file (sort @files) {
    ok(do {
        my $tv = 0;
        my $w;
        eval {
            $w = Workflow::Model->create_from_xml($dir . '/' . $file);
        };
        if ($@) {
            if ($file =~ /_invalid/) {
                $tv = 1;
            }
        } else {
            $w->validate;
            if ($file =~ /_invalid/) {
                $tv = 1 unless $w->is_valid;
            } else {
                $tv = 1 if $w->is_valid;
            }
        }
        $tv
    },'load and validate ' . $file);
}
