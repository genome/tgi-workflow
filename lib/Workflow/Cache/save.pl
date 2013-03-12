#! /usr/bin/perl

use Workflow;
use IO::File;

my $xml_filename = $ARGV[0];
die "Couldn't find xml filename at $xml_filename" unless -s $xml_filename;

my $fh = IO::File->new($xml_filename);
my $xml;
{
    local ($/);
    $xml = <$fh>;
}

my $cache = Workflow::Cache->create(xml=>$xml);

if (UR::Context->commit()) {
    print STDOUT $cache->id . "\n";
} else {
    exit 1;
}

exit 0;
