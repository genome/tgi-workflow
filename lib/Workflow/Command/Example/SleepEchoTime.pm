package Cord::Command::Example::SleepEchoTime;

class Cord::Command::Example::SleepEchoTime {
    is => ['Cord::Operation::Command'],
    workflow => sub { 
        my $file = __FILE__;
        $file =~ s/\.pm$/.xml/;
        Cord::Operation->create_from_xml($file); 
    }
};

1;
