
package Workflow::Server::HTTPD;

use strict;
use base 'Workflow::Server';
use POE qw(Component::Server::TCP Filter::HTTPD);

use URI;
use URI::QueryParam;

use Workflow ();

sub setup {

    our $httpd = POE::Component::Server::TCP->new(
        Alias        => "httpd",
        Port         => 8088,
        ClientFilter => 'POE::Filter::HTTPD',
        ClientInput  => sub {
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

            $heap->{request} = $request;
            my $uri = $request->uri;
            $uri->scheme('http');
            $uri->host($request->header('host'));
            
            my $query = $heap->{query} = $uri->query_form_hash;

            print $request->as_string;
            print "scheme: " . $uri->scheme . "\n";
            print "host: " . $uri->host . "\n";
            print "path: " . $uri->path . "\n";
            print "path_segments: " . join(',', $uri->path_segments) . "\n";
            print "query: " . $uri->query . "\n";
            print "query_form_hash:\n";
            print Data::Dumper->new([$uri->query_form_hash])->Dump . "\n";

            my $response = HTTP::Response->new(200);
            $heap->{response} = $response;

            my $function = ($uri->path_segments)[1];

            if ($function eq 'summary') {
                $kernel->yield('status_summary');
            } elsif ($function eq 'browse') {
                $kernel->yield('object_browser');
            } else {
                $kernel->yield('not_found','function');
            }
        },
        InlineStates => {
            exception => sub {
                my ($kernel,$heap,$message) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                
                $response->content(
                    "<html><head><title>Died</title></head>" .
                    "<body><pre>$message</pre></body></html>"
                );

                $kernel->yield('finish_response');
            },
            not_found => sub {
                my ($kernel,$heap,$thing) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                
                $response->code('404');
                $response->push_header( 'Content-type', 'text/plain' );
                
                $response->content("Cannot find what $thing you're looking for.\n");
                $kernel->yield('finish_response');                
            },
            object_browser => sub {
                my ($kernel,$heap) = @_[KERNEL,HEAP];
                my $response = $heap->{response};
                my $uri = $heap->{request}->uri;
                
                my $class = ($uri->path_segments)[2];
                return $kernel->yield('not_found','class') unless $class;

                my $object_id = ($uri->path_segments)[3] ? '"' . ($uri->path_segments)[3] . '"' : '';
#                return $kernel->yield('not_found','object identifier') unless $object_id;
                
                
                $kernel->post(
                    'IKC','call',
                    'poe://UR/workflow/eval',
                    [q{
                        my @objects = } . $class . q{->is_loaded(} . $object_id . q{);
                    
                        my %dump;
                        foreach my $object (@objects) {
                            my $class = $object->get_class_object;
                            my $object_name = $class->class_name . '=' . $object->id;
                            
                            $dump{$object_name} ||= {
                                has => {},
                                calculated => {},
                                delegated => {},
                                via => {},
                                many => {}
                            };
                            foreach my $prop ($class->get_all_property_objects) {
                                my $name = $prop->property_name;
                                if ($prop->is_many) {
                                    my @stuff = $object->$name;
                                
                                    my @names = map { $_->class . '=' . $_->id } @stuff;
                                
                                    $dump{$object_name}{many}{$name} = \@names;
                                } elsif ($prop->is_calculated) {
                                    $dump{$object_name}{calculated}{$name} = $object->$name;
                                } elsif ($prop->via) {
                                    $dump{$object_name}{via}{$prop->via} ||= {};
                                    $dump{$object_name}{via}{$prop->via}{$name} = $object->$name;
                                } elsif ($prop->is_delegated) {
#                                    $dump{$object_name}{delegated}{$name} = $object->$name;
                                    my $thing = $object->$name;
                                    if ($thing) {
                                        $dump{$object_name}{delegated}{$name} = $thing->class . '=' . $thing->id;
                                    } else {
                                        $dump{$object_name}{delegated}{$name} = 'undef';
                                    }
                                } else {
                                    $dump{$object_name}{has}{$name} = $object->$name;
                                }
                            }
                        }
                        return %dump;
                    },1],
                    'poe:got_object_dump'
                );
            },
            got_object_dump => sub {
                my ($kernel,$heap,$arg) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                my ($ok,$result) = @$arg;

                return $kernel->yield('exception',$result) unless $ok;
                return $kernel->yield('not_found','object') unless $result;
                
                $response->push_header('Content-type','text/html');
                my %h = (@$result);

                $response->content('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"><html><body>');
                $response->add_content(<<MARK);
<head>
 <style>
  table {
    border: 2px solid black;
  }
  .objectname {
    background-color: #58EFBF;
  }
  .sectionname {
    background-color: #8FEFBF;
  }
  td:first-child + td + td, .value { 
    font-family: monospace;
  }
  td:first-child {
    padding-left: 40px;
    vertical-align: top;
  }
  .objectname td:first-child {
    padding-left: 0px;
  }
  .sectionname td:first-child {
    padding-left: 20px;
  }
  pre {
    margin-top: 0px;
    margin-bottom: 0px;
  }
 </style>
</head>
MARK

                my $html = '<table><colgroup><col class=property /><col class=source /><col class=value /></colgroup>';
                $html .= '<thead><tr><th>Property</th><th>Source</th><th>Value</th></tr></thead>';

                my %sortorder = (
                    has => 0,
                    calculated => 10,
                    via => 20,
                    delegated => 30,
                    many => 40
                );

                while (my ($oname,$odesc) = each(%h)) {
                    $html .= "<tr class=objectname><td colspan=3>$oname</td></tr>";
                    foreach my $psecn (sort { $sortorder{$a} <=> $sortorder{$b} } keys %$odesc) {
                        my $psecd = $odesc->{$psecn};
                        $html .= "<tr class=sectionname><td colspan=3>$psecn</td></tr>";
#                        while (my ($propn,$propv) = each(%$psecd)) {
                        foreach my $propn (sort keys %$psecd) {
                            my $propv = $psecd->{$propn};
                            if ($psecn eq 'via') {
#                                while (my ($vian,$viav) = each(%$propv)) {
                                foreach my $vian (sort keys %$propv) {
                                    my $viav = $propv->{$vian};
                                    my $value = Data::Dumper->new([$viav])->Useqq(1)->Dump;
                                    $html .= "<tr><td>$vian</td><td>$propn</td><td><pre>$value</pre></td></tr>";
                                }
                            } elsif ($psecn eq 'many') {
                                my $name = $propn;
                                foreach my $value (@$propv) {
                                    my ($package,$id) = split('=',$value);
                                    my $link="/browse/$package/$id";
                                
                                    $html .= "<tr><td>$name</td><td></td><td><pre><a href='$link'>$value</a></pre></td></tr>";
                                    $name = '';
                                }
                            } elsif ($psecn eq 'delegated') {
                                my ($package,$id) = split('=',$propv);
                                
                                my $link="/browse/$package/$id";
                                $html .= "<tr><td>$propn</td><td></td><td><pre><a href='$link'>$propv</a></pre></td></tr>";
                            } else {
                                my $value = Data::Dumper->new([$propv])->Useqq(1)->Dump;
                                $html .= "<tr><td>$propn</td><td></td><td><pre>$value</pre></td></tr>";
                            }
                        }
                    }
                }
                $html .= '</table>';
                
                $response->add_content($html);
                $response->add_content('</body></html>');
                
#                $response->content(Data::Dumper->new([\%h])->Useqq(1)->Dump);
                $kernel->yield('finish_response');

            },
            status_summary => sub {
                my ($kernel,$heap) = @_[KERNEL,HEAP];
                my $response = $heap->{response};

                $response->push_header('Content-type', 'text/html');
                $response->content(
                    "<html><head><title>Server status summary</title></head>" .
                    "<body><table border=1><tr><th>Type</th><th>New</th><th>Scheduled</th>" .
                    "<th>Running</th><th>Done</th><th>Crashed</th></tr>"
                );

                $kernel->post(
                    'IKC','call',
                    "poe://UR/workflow/eval",
                    [
                        q{
                            my @instance = Workflow::Operation::Instance->is_loaded(parent_instance_id => undef);

                            my %counts;
                            foreach my $i (@instance) {
                                my $type = ref($i->operation->operation_type);
                                if ($type eq 'Workflow::OperationType::Command') {
                                    $type = $i->operation->operation_type->command_class_name;
                                }

                                $counts{$type}{$i->status} ||= 0;
                                $counts{$type}{$i->status}++;
                            }
                            return %counts;
                        },
                        1
                    ],
                    "poe:got_counts"
                );            
            },
            got_counts => sub {
                my ($kernel,$heap,$arg) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                my ($ok,$result) = @$arg;

                return $kernel->yield('exception',$result) unless $ok;
                my %counts = (@$result);
                
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

                $kernel->yield('finish_response');
            },
            finish_response => sub {
                my ($kernel,$heap) = @_[KERNEL,HEAP];
                
                $heap->{client}->put($heap->{response});
                $kernel->yield("shutdown");                
            }
        }
    );
}

1;
