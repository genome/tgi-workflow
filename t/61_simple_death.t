#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

plan tests => 11;

use above 'Workflow';
use Workflow::Simple;

#$Workflow::Simple::override_lsf_use = 1;
$Workflow::Simple::store_db = 0;

my $output;

$output = run_workflow_lsf(
    \*DATA, 
    'model input string' => 'foo bar baz',
    'sleep time' => 0 
);

ok(!defined $output,'output not defined');
ok(scalar(@Workflow::Simple::ERROR) == 1, 'one error');
ok($Workflow::Simple::ERROR[0]->error =~ /death by test case/, 'error message correct');

my $op;
$op = Workflow::Operation->create(
    name => 'death to all',
    operation_type => Workflow::OperationType::Command->get('Workflow::Test::Command::Die')
);
$op->parallel_by('seconds');

$output = run_workflow_lsf(
    $op,
    seconds => [1,2,3]
);

ok(!defined $output,'output not defined');

ok(scalar(@Workflow::Simple::ERROR) == 3, 'three errors');
for (0..2) {
    ok($Workflow::Simple::ERROR[$_]->error =~ /death by test case/, 'error message correct');
}

my $model = Workflow::Model->create(
    name => 'some finish and some die',
    input_properties => [ 'die_seconds', 'sleep1_seconds', 'sleep2_seconds' ],
    output_properties => [ 'die_result', 'sleep1_result', 'sleep2_result' ]
);

my $die = $model->add_operation(
    name => 'die',
    operation_type => Workflow::OperationType::Command->get('Workflow::Test::Command::Die')
);


$model->add_link(
    left_operation => $model->get_input_connector,
    left_property => 'die_seconds',
    right_operation => $die,
    right_property => 'seconds'
);

$model->add_link(
    left_operation => $die,
    left_property => 'result',
    right_operation => $model->get_output_connector,
    right_property => 'die_result'
);

my $sleep1 = $model->add_operation(
    name => 'sleep1',
    operation_type => Workflow::OperationType::Command->get('Workflow::Test::Command::Sleep')
);


$model->add_link(
    left_operation => $model->get_input_connector,
    left_property => 'sleep1_seconds',
    right_operation => $sleep1,
    right_property => 'seconds'
);

$model->add_link(
    left_operation => $sleep1,
    left_property => 'result',
    right_operation => $model->get_output_connector,
    right_property => 'sleep1_result'
);

my $sleep2 = $model->add_operation(
    name => 'sleep2',
    operation_type => Workflow::OperationType::Command->get('Workflow::Test::Command::Sleep')
);

$model->add_link(
    left_operation => $model->get_input_connector,
    left_property => 'sleep2_seconds',
    right_operation => $sleep2,
    right_property => 'seconds'
);

$model->add_link(
    left_operation => $sleep2,
    left_property => 'result',
    right_operation => $model->get_output_connector,
    right_property => 'sleep2_result'
);

$output = run_workflow_lsf(
    $model,
    die_seconds => 2,
    sleep1_seconds => 30,
    sleep2_seconds => 30
);

ok(!defined $output,'output not defined');

ok(scalar(@Workflow::Simple::ERROR) == 2, 'two errors');
ok($Workflow::Simple::ERROR[0]->error =~ /death by test case/, 'error message correct');

__DATA__
<?xml version='1.0' standalone='yes'?>
<workflow name="Example Workflow" executor="Workflow::Executor::SerialDeferred">
  <link fromOperation="input connector" fromProperty="sleep time" toOperation="sleep" toProperty="seconds" />
  <link fromOperation="echo" fromProperty="result" toOperation="wait for sleep and echo" toProperty="echo result" />
  <link fromOperation="wait for sleep and echo" fromProperty="echo result" toOperation="output connector" toProperty="result" />
  <link fromOperation="echo" fromProperty="output" toOperation="output connector" toProperty="model output string" />
  <link fromOperation="sleep" fromProperty="result" toOperation="wait for sleep and echo" toProperty="sleep result" />
  <link fromOperation="input connector" fromProperty="model input string" toOperation="echo" toProperty="input" />
  <link fromOperation="time" fromProperty="today" toOperation="output connector" toProperty="today" />
  <operation name="wait for sleep and echo">
    <operationtype typeClass="Workflow::OperationType::Block">
      <property>echo result</property>
      <property>sleep result</property>
    </operationtype>
  </operation>
  <operation name="sleep">
    <operationtype commandClass="Workflow::Test::Command::Die" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="echo">
    <operationtype commandClass="Workflow::Test::Command::Echo" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="time">
    <operationtype commandClass="Workflow::Test::Command::Time" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operationtype typeClass="Workflow::OperationType::Model">
    <inputproperty>model input string</inputproperty>
    <inputproperty>sleep time</inputproperty>
    <outputproperty>model output string</outputproperty>
    <outputproperty>result</outputproperty>
    <outputproperty>today</outputproperty>
  </operationtype>
</workflow>
