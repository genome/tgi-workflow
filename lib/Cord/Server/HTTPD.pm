
package Cord::Server::HTTPD;

use strict;
use base 'Cord::Server';
use POE qw(Component::Server::TCP Filter::HTTPD);

use URI;
use URI::QueryParam;

use Cord ();

our $server_and_port;
our $server_channel;

sub setup {

    our $monitor = POE::Session->create(
        inline_states => {
            _start => sub {
                my ($kernel) = @_[KERNEL];
                POE::Component::IKC::Responder->spawn();

#                $kernel->post('IKC','monitor','*'=>{register=>'reg',unregister=>'unreg',subscribe=>'sub',unsubscribe=>'unsub'});
            },
            reg => sub {
                my ($name,$real) = @_[ARG1,ARG2];

                print "connect ", ($real ? '' : 'alias '), "$name\n";
            },
            unreg => sub {
                my ($name,$real) = @_[ARG1,ARG2];

                $server_and_port = undef;
                $server_channel = undef;

                print "disconnect ", ($real ? '' : 'alias '), "$name\n";
            },
            'sub' => sub {
                my ($name,$real) = @_[ARG1,ARG2];

                print "joined ", ($real ? '' : 'alias '), "$name\n";
            }, 
            unsub => sub {
                my ($name,$real) = @_[ARG1,ARG2];

                print "left ", ($real ? '' : 'alias '), "$name\n";
            }
        }
    );

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

=pod
            print $request->as_string;
            print "scheme: " . $uri->scheme . "\n";
            print "host: " . $uri->host . "\n";
            print "path: " . $uri->path . "\n";
            print "path_segments: " . join(',', $uri->path_segments) . "\n";
            print "query: " . $uri->query . "\n";
            print "query_form_hash:\n";
            print Data::Dumper->new([$uri->query_form_hash])->Dump . "\n";
=cut

            my $response = HTTP::Response->new(200);
            $heap->{response} = $response;

            my $advanced = $heap->{advanced} = ($uri->query eq 'advanced' ? $uri->query : undef);

            my @segments = $uri->path_segments;

            my $function = $segments[1];
            if ($function eq 'switch' || defined $server_and_port) {
                if ($function eq 'servers') {
                    $kernel->yield('servers');
                } elsif ($function eq 'switch') {
                    $kernel->yield('switch');
                } elsif ($function eq 'summary') {
                    $kernel->yield('status_summary');
                } elsif ($function eq 'browse') {
                    $kernel->yield('object_browser');
                } elsif ($function eq 'abandon' && $advanced) {
                    $kernel->yield('abandon');
                } elsif ($function eq 'lsf') {
                    $kernel->yield('bjobs');
                } elsif ($function eq 'poke' && $advanced) {
                    $kernel->yield('poke');
                } elsif ($function eq 'kill' && $advanced) {
                    $kernel->yield('kill');
                } elsif ($function eq '') {
                    $kernel->yield('servers');
                } else {
                    $kernel->yield('not_found','function');
                }
            } else {
                $kernel->yield('servers');
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
            'servers' => sub {
                my ($kernel,$heap) = @_[KERNEL,HEAP];
                my $response = $heap->{response};

                my $advanceduri = ($heap->{advanced} ? '?' . $heap->{advanced} : '');

                $response->push_header('Content-type', 'text/html');
                $response->content(
                    "<html><head><title>Server list</title></head>" .
                    "<body><h1>All servers:</h1><table border=1><tr><th>Hostname:Port</th><th>Username</th><th>Process ID</th><th>Start Time</th><th>Running</th></tr>"
                );


                $heap->{run_results} = {};

                my @servers = Cord::Service->load();
                foreach my $s (sort { Cord::Time->compare_dates($a->start_time,$b->start_time) }@servers) {
                    my $hostname = $s->hostname;
                    my $port = $s->port;

                    my $hp = "$hostname:$port";

                    if (defined $server_and_port && $hp eq $server_and_port) {
                        $hp = '<b>' . $hp . '</b>';
                    }

                    $response->add_content("<tr><td><a href=\"/switch/$hostname:$port$advanceduri\">$hp</a></td><td>" . join("</td><td>", $s->username, $s->process_id, $s->start_time) . "</td></tr>");
                    
                    
                    $heap->{run_result}->{"$hostname:$port"};
                }
                
                Cord::Service->unload();

                $response->add_content("</table>");
                $kernel->yield('finish_response');
            },
            
            'switch' => sub {
                my ($kernel,$heap,$session) = @_[KERNEL,HEAP,SESSION];
                my $response = $heap->{response};
                my $uri = $heap->{request}->uri;

                my $server_port = ($uri->path_segments)[2];
                my ($ur_host,$ur_port) = split(':', $server_port);

                if ($server_port eq $server_and_port) {
                    $kernel->yield('finish_switch');
                    return;
                }

                if (defined $server_channel) {
                    $kernel->call($server_channel => 'shutdown');
                }

                my $web_client_session_id = $session->ID;
                POE::Component::IKC::Client->spawn(
                    ip => $ur_host,
                    port => $ur_port,
                    name => 'HTTPD',
                    on_connect => sub {
                        $server_and_port = $server_port;
                        $server_channel = $poe_kernel->get_active_session()->ID;

                        $poe_kernel->post($web_client_session_id => 'finish_switch');
                    },
                    on_error => sub {
                        my ($op, $errnum, $errstr) = @_;

                        print "arggg $op $errnum $errstr\n";
                        $poe_kernel->post($web_client_session_id => 'finish_switch');
                    }
                ); 
            },
            'finish_switch' => sub {
                my ($kernel,$heap,$session) = @_[KERNEL,HEAP,SESSION];
                my $response = $heap->{response};

                my $advanceduri = ($heap->{advanced} ? '?' . $heap->{advanced} : '');

                $response->code('302');
                $response->push_header('Location','http://' . $heap->{request}->uri->host  . ':8088/summary' . $advanceduri);

                $kernel->yield('finish_response');
            },
            'kill' => sub {
                my ($kernel,$heap) = @_[KERNEL,HEAP];
                my $response = $heap->{response};
                my $uri = $heap->{request}->uri;

                my $id = ($uri->path_segments)[2];
                return $kernel->yield('not_found','lsf_job_id') unless $id;

                $kernel->post(
                    'IKC','call',
                    'poe://UR/workflow/eval',
                    [q{
                        system('bkill } . $id . q{');
                        return 1;
                    },0],
                    'poe:got_poked'
                );

            },
            got_kill => sub {
                my ($kernel,$heap,$arg) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                my ($ok,$result) = @$arg;

                return $kernel->yield('exception',$result) unless $ok;
                return $kernel->yield('not_found','result') unless $result;

                my $advanceduri = ($heap->{advanced} ? '?' . $heap->{advanced} : '');

                $response->code('302');
                $response->push_header('Location','http://' . $heap->{request}->uri->host  . ':8088/summary' . $advanceduri);

                $kernel->yield('finish_response');

            },
            poke => sub {
                my ($kernel,$heap) = @_[KERNEL,HEAP];
                my $response = $heap->{response};
                my $uri = $heap->{request}->uri;

                my $id = ($uri->path_segments)[2];
                return $kernel->yield('not_found','instance_id') unless $id;

                $kernel->post(  
                    'IKC','call',
                    'poe://UR/workflow/eval',
                    [q{
                        my $i = Cord::Operation::Instance->is_loaded(} . $id . q{);
                        $i->is_running(1);
                        $i->resume;
                        return $i;
                    },0],
                    'poe:got_poked'
                );
            },
            got_poked => sub {
                my ($kernel,$heap,$arg) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                my ($ok,$result) = @$arg;

                return $kernel->yield('exception',$result) unless $ok;
                return $kernel->yield('not_found','object') unless $result;

                my $advanceduri = ($heap->{advanced} ? '?' . $heap->{advanced} : '');

                $response->code('302'); 
                $response->push_header('Location','http://' . $heap->{request}->uri->host  . ':8088/summary' . $advanceduri);

                $kernel->yield('finish_response');
            },
            abandon => sub {
                my ($kernel,$heap) = @_[KERNEL,HEAP];
                my $response = $heap->{response};
                my $uri = $heap->{request}->uri;

                my $id = ($uri->path_segments)[2];
                return $kernel->yield('not_found','instance_id') unless $id;

                unless ($id =~ /^\d+/) {
                    $id = "'$id'";
                }

                $kernel->post(   
                    'IKC','call',
                    'poe://UR/workflow/eval',
                    [q{
                        my $i = Cord::Operation::Instance->is_loaded(} . $id . q{);
                        $i->is_running(0);
                        $i->status('crashed');
                        $i->completion;
                        return $i;
                    },0],
                    'poe:got_abandon'
                );
            },
            got_abandon => sub {
                my ($kernel,$heap,$arg) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                my ($ok,$result) = @$arg;

                return $kernel->yield('exception',$result) unless $ok;
                return $kernel->yield('not_found','object') unless $result;

                my $advanceduri = ($heap->{advanced} ? '?' . $heap->{advanced} : '');

                $response->code('302');
                $response->push_header('Location','http://' . $heap->{request}->uri->host  . ':8088/summary' . $advanceduri);

                $kernel->yield('finish_response');
            },
            bjobs => sub {
                my ($kernel,$heap) = @_[KERNEL,HEAP];
                my $response = $heap->{response};
                my $uri = $heap->{request}->uri;
                
                my $job_id = ($uri->path_segments)[2];
                return $kernel->yield('not_found','job_id') unless $job_id;
                
                $response->push_header('Content-type','text/plain');
                my $out = `bjobs -l $job_id 2>&1`;
                $response->content($out);
                
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
                            foreach my $prop ($class->all_property_metas) {
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
                        foreach my $propn (sort keys %$psecd) {
                            my $propv = $psecd->{$propn};
                            if ($psecn eq 'via') {
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
                my $advanceduri = ($heap->{advanced} ? '?' . $heap->{advanced} : '');

                $response->push_header('Content-type', 'text/html');
                $response->content(
                    "<html><head><title>Summary</title></head>" .
                    "<body><b>Current Server:</b> $server_and_port <a href=\"/servers$advanceduri\">Server List</a><br>" . 
                    "<h1>Root-level workflow instances:</h1><table border=1><tr><th>Id</th><th>Name</th><th>Status</th><th></th></tr>" 
                    
                );

                $kernel->post(
                    'IKC','call',
                    "poe://UR/workflow/eval",
                    [
                        q{
                            my @instance = Cord::Operation::Instance->is_loaded(parent_instance_id => undef);

                            my %infos = ();
                            foreach my $i (@instance) {
                                if (defined $i->peer_instance_id && $i->peer_instance_id ne $i->id) {
                                    next;
                                }

                                $infos{$i->id} = [$i->name,$i->status];
                            }
                            return %infos;
                        },
                        1
                    ],
                    "poe:got_info"
                );            
            },
            got_info => sub {
                my ($kernel,$heap,$arg) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                my ($ok,$result) = @$arg;

                my $advanceduri = ($heap->{advanced} ? '?' . $heap->{advanced} : '');

                return $kernel->yield('exception',$result) unless $ok;
                my %infos = (@$result);
                
                while (my ($id,$info) = each (%infos)) {
                    my ($name, $status) = @{ $info };
                    
                    my $link = '/browse/Cord::Operation::Instance/' . $id;
                    
                    $response->add_content("<tr><td>$id</td><td><a href=\"$link\">$name</a></td><td>$status</td>");
                    $response->add_content("<td><a href=\"/abandon/$id$advanceduri\">Kill</a></tr>") if ($heap->{advanced});
                    $response->add_content("</tr>");
                }

                $response->add_content("</table><h1>Instances of interest:</h1><table border=1><tr><th>Id</th><th>Name</th><th>Status</th><th>Result</th><th>LSF Job Id</th><th></th><th></th></tr>");
                
                $kernel->post(
                    'IKC','call',
                    "poe://UR/workflow/eval",
                    [
                        q{
                            my @instance = Cord::Operation::Instance->is_loaded();
                            
                            my %infos = ();
                            foreach my $i (@instance) {
                                if ($i->can('child_instances')) {
                                    next;
                                }
                                my $result;
                                if (exists($i->output->{result})) {
                                    if (defined $i->output->{result}) {
                                        $result = $i->output->{result};
                                    } else {
                                        $result = '(undef)';
                                    }
                                } else {
                                    $result = '';
                                }

                                next unless ($i->is_running() || $i->status eq 'running' || $i->status eq 'crashed' || $result eq '(undef)');
                                
                                $infos{$i->id} = [$i->name,$i->status,$result,$i->current->dispatch_identifier];
                            }
                            
                            return %infos;
                        },
                        1
                    ],
                    "poe:got_leaves"
                );
            },
            got_leaves => sub {
                my ($kernel,$heap,$arg) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                my ($ok,$result) = @$arg;

                my $advanceduri = ($heap->{advanced} ? '?' . $heap->{advanced} : '');

                return $kernel->yield('exception',$result) unless $ok;
                my %infos = (@$result);
                
#                while (my ($id,$info) = each (%infos)) {
                foreach my $id ( sort { $a <=> $b } keys %infos ) {
                    my $info = $infos{$id};
                    my ($name, $status, $opresult, $dispatch_id) = @{ $info };
                    
                    my $link = '/browse/Cord::Operation::Instance/' . $id;
                    
                    $response->add_content("<tr><td>$id</td><td><a href=\"$link\">$name</a></td><td>$status</td><td>$opresult</td><td><a href=\"/lsf/$dispatch_id\">$dispatch_id</a></td>");
                    $response->add_content("<td><a href=\"/kill/$dispatch_id$advanceduri\">Kill</a></td><td><a href=\"/poke/$id$advanceduri\">Resume</a></td>") if ($heap->{advanced});
                    $response->add_content("</tr>");
                }

                $response->add_content("</table><h1>Errors encountered:</h1><table border=1><tr><th>Instance Id</th><th>Path Name</th><th>Error</th></tr>");

                $kernel->post(
                    'IKC','call',
                    "poe://UR/workflow/eval",
                    [
                        q{
                            my @errors = Cord::Operation::InstanceExecution::Error->is_loaded();
                            
                            my %infos = ();
                            foreach my $e (@errors) {
                                $infos{$e->id} = [
                                    $e->instance_id,
                                    $e->path_name,
                                    $e->name,
                                    $e->error
                                ];
                            }
                            
                            return %infos;
                        },
                        1
                    ],
                    "poe:got_error_list"
                );

            },
            got_error_list => sub {
                my ($kernel,$heap,$arg) = @_[KERNEL,HEAP,ARG0];
                my $response = $heap->{response};
                my ($ok,$result) = @$arg;

                return $kernel->yield('exception',$result) unless $ok;
                my %infos = (@$result);
                
                while (my ($id,$info) = each (%infos)) {
                    my ($instance_id, $path_name, $name, $error) = @{ $info };
                    
                    my $link = '/browse/Cord::Operation::InstanceExecution::Error/' . $id;
                    
                    $response->add_content("<tr><td>$instance_id</td><td><a href=\"$link\">$path_name</a></td><td><pre>$error</pre></td></tr>");
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
