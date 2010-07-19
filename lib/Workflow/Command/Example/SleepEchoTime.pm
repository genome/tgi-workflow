package Workflow::Command::Example::SleepEchoTime;

class Workflow::Command::Example::SleepEchoTime {
    is => ['Workflow::Operation::Command'],
    workflow => sub { 
        my $file = __FILE__;
        $file =~ s/\.pm$/.xml/;
        Workflow::Operation->create_from_xml($file); 
    }
};

1;
