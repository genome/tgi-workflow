
package Workflow::Server::HTTPD;

use strict;

use POE qw(Component::Server::TCP Filter::HTTPD);
use Workflow ();

sub start {

    our $httpd = POE::Component::Server::TCP->new(
        Alias => "web_server",
        Port         => 8088,
        ClientFilter => 'POE::Filter::HTTPD',
        ClientInput => \&_client_input
    );
}

sub _client_input {
    my ( $kernel, $heap, $request ) = @_[ KERNEL, HEAP, ARG0 ];

    # Filter::HTTPD sometimes generates HTTP::Response objects.
    # They indicate (and contain the response for) errors that occur
    # while parsing the client's HTTP request.  It's easiest to send
    # the responses as they are and finish up.

    if ( $request->isa("HTTP::Response") ) {
        $heap->{client}->put($request);
        $kernel->yield("shutdown");
        return;
    }

    # The request is real and fully formed.  Build content based on
    # it.  Insert your favorite template module here, or write your
    # own. :)

    my $response = HTTP::Response->new(200);
    $response->push_header( 'Content-type', 'text/html' );
    $response->content(
        "<html><head><title>Server status summary</title></head>" .
        "<body><table><tr><th>Type</th><th>New</th><th>Scheduled</th><th>Running</th><th>Done</th><th>Crashed</th></tr>"
    );
    
    # Multilevel hash of counts. Format is $counts{Type}{Status} = Number
    
    my %counts = ();

    my @instance = Workflow::Operation::Instance->all_objects_loaded;
    foreach my $i (@instance) {
        my $type = ref($i->operation->operation_type);
        if ($type eq 'Workflow::OperationType::Command') {
            $type = $i->operation->operation_type->command_class_name;
        }
        
        $counts{$type}{$i->status} ||= 0;
        $counts{$type}{$i->status}++;
    }
    
    while (my ($type,$h) = each(%counts)) {
        $response->add_content("<tr><td>$type</td>");

        for my $n (qw/new scheduled running done crashed/) {
            $response->add_content(
                "<td>" . (defined $h->{$n} ? $h->{$n} : '') . '</td>'
            );
        }
        $response->add_content("</tr>");
    }
    
    $response->add_content(
        "</table></body></html>"
    );

    # Once the content has been built, send it back to the client
    # and schedule a shutdown.

    $heap->{client}->put($response);
    $kernel->yield("shutdown");
}

1;
