
package Workflow::Server::HTTPD;

use strict;

use POE qw(Component::Server::TCP Filter::HTTPD);
use Workflow ();

our $singleton;

sub new {
    my $class = shift;
    
    return $singleton || bless({},$class);
}

sub create {
    my $class = shift;
    my $self = $class->new();
    $singleton = $self;

    $self->{session} = POE::Component::Server::TCP->new(
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
        "<body><table><tr><th>Type</th><th>Status</th><th>Count</th></tr>"
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
        while (my ($status, $count) = each( %$h )) {
            $response->add_content(
                "<tr><td>$type</td><td>$status</td><td>$count</td></tr>"
            );
        }
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
