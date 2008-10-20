#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

my $static_test_count = 16;

use Workflow;
my @subcommands = Workflow::Test::Command->sub_command_classes;

plan tests => $static_test_count + scalar(@subcommands);

require_ok('Workflow');
require_ok('Workflow::OperationType::Command');

{

    my $o1 = Workflow::OperationType::Command->create(
        command_class_name => 'Workflow::Test::Command::Sleep'
    );

    ok($o1,'create');
    is($o1->command_class_name,'Workflow::Test::Command::Sleep','command class name');
    
    ok(eq_set($o1->input_properties,['seconds']),'input properties');
    ok(eq_set($o1->output_properties,['result']),'output properties');
    is($o1->lsf_queue,'short','lsf queue');
    is($o1->lsf_resource,'rusage[mem=4000] span[hosts=1]','lsf resource');
    
    my $o2 = Workflow::OperationType::Command->create(
        command_class_name => 'Workflow::Test::Command::Sleep'
    );

    is($o2->id,$o1->id,'multiple create returns same object');    
}

{ ## test old style operation definition
    my $o1 = Workflow::OperationType::Command->create(
        command_class_name => 'Workflow::Test::Command::DeprecatedOperationDefinition'
    );

    ok($o1,'old format -create');

    is($o1->command_class_name,'Workflow::Test::Command::DeprecatedOperationDefinition','old format -command class name');

    ok(eq_set($o1->input_properties,[]),'old format -input properties');
    ok(eq_set($o1->output_properties,[qw/today now result/]),'old format -output properties');
    is($o1->lsf_queue,'long','old format -lsf queue');
    is($o1->lsf_resource,'rusage[tmp=100]','old format -lsf resource');

    my $o2 = Workflow::OperationType::Command->create(
        command_class_name => 'Workflow::Test::Command::DeprecatedOperationDefinition'
    );

    is($o2->id,$o1->id,'old format -multiple create return same object');
}

# try to instantiate all our test command modules, just to be sure

foreach my $cmd (@subcommands) {
    my $o = Workflow::OperationType::Command->create(
        command_class_name => $cmd
    );
    
    isa_ok($o,'Workflow::OperationType::Command',$cmd);
}


