#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

plan tests => 2;

use above 'Workflow';
use Workflow::Simple;

#$Workflow::Simple::override_lsf_use = 1;
$Workflow::Simple::store_db = 0;

my $op = Workflow::Operation->create(
    name => 'watchdog',
    operation_type => Workflow::OperationType::Command->get('Workflow::Test::Command::Watchdog')
);

my $output = run_workflow_lsf(
    $op,
    seconds => 120 
);

print Data::Dumper->new([$output,\@Workflow::Simple::ERROR])->Dump;


