package Workflow::Env;

if (-d '/gsc') {
    # This shouldn't be in the workflow code proper but this 
    # module is being eliminated by the workflow replacement project.
    # If this stayed around we should move this into organization-wide environment variables or a config file.
    $ENV{WF_SERVER_QUEUE} ||= 'workflow'; 
    $ENV{WF_TEST_QUEUE} ||= 'short';
    $ENV{WF_JOB_QUEUE} ||= 'apipe';
}
else {
    $ENV{WF_SERVER_QUEUE} ||= 'normal'; 
    $ENV{WF_TEST_QUEUE} ||= 'normal';
    $ENV{WF_JOB_QUEUE} ||= 'normal';
}

1;

