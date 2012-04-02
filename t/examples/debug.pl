#!/gsc/bin/perl

use strict;
use warnings;

use above 'Cord';
use Data::Dumper;
use PAP;

my $i = Cord::Store::Db::Operation::Instance->get(28);

$i->treeview_debug;

#print "test\n";


#print Data::Dumper->new([$i])->Dump;
