package Workflow::Env;

$ENV{WF_SERVER_QUEUE} ||= 'normal';
$ENV{WF_TEST_QUEUE} ||= 'normal';
$ENV{WF_JOB_QUEUE} ||= 'normal';

