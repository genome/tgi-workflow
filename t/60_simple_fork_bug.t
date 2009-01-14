#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

my $pid = fork();
if (not defined $pid) {
    die 'cant fork';
} elsif ($pid == 0) {
    sleep 300;
    exit(0);
} else {

    plan tests => 2;

    use above 'Workflow';
    use Workflow::Simple;

    $Workflow::Simple::store_db = 0;

    my $output = run_workflow_lsf(
        \*DATA, 
        'model input string' => 'foo bar baz',
        'sleep time' => 1 
    );

#    print Data::Dumper->new([$output,\@Workflow::Simple::ERROR])->Dump;

    ok($output->{'model output string'} eq 'foo bar baz', 'string is correct');

#    waitpid($pid,0);
}
ok(1,'past forking code');

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
    <operationtype commandClass="Workflow::Test::Command::Sleep" typeClass="Workflow::OperationType::Command" />
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
