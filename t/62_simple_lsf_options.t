#!/usr/bin/env perl

BEGIN {
    # test only passes with Flow disabled
    $ENV{WF_USE_FLOW} = 0;

    $ENV{UR_DBI_NO_COMMIT}=1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS}=1;
}

use strict;
use warnings;
use Test::More;

plan tests => 6;

use File::Temp;

use above 'Workflow';
use Workflow::Simple;

$ENV{WF_TESTDIR} = File::Temp::tempdir('WorkflowXXXXX', DIR => $ENV{GENOME_TEST_TEMP}, CLEANUP => 1);

my $op = Workflow::Operation->create(
    name => 'ls',
    operation_type => Workflow::OperationType::Command->get('Workflow::Test::Command::Ls')
);

my $output = run_workflow_lsf(
    $op,
);

ok(defined $output,'defined');
ok(-e $ENV{WF_TESTDIR} . '/stdout', 'stdout exists');
ok(-e $ENV{WF_TESTDIR} . '/stderr', 'stderr exists');

$op->operation_type->lsf_resource(' ' . $op->operation_type->lsf_resource);

$output = run_workflow_lsf(
    $op,
);

ok(defined $output,'w/ space defined');
ok(-e $ENV{WF_TESTDIR} . '/stdout', 'w/ space stdout exists');
ok(-e $ENV{WF_TESTDIR} . '/stderr', 'w/ space stderr exists');


