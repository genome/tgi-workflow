#!/gsc/bin/perl

use strict;
use warnings;

use above 'Workflow';
use Data::Dumper;
use PAP;

my $i = Workflow::Store::Db::Operation::Instance->get(5639);

$i->treeview_debug;

#print "test\n";


#print Data::Dumper->new([$i->output])->Dump;
