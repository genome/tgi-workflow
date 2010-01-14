# This class is a remote control for workflow servers.

package Workflow::Server::Remote;

use strict;
use warnings;
use Carp;
use POE::Component::IKC::ClientLite;

use Guard;
use IPC::Run;
use Socket;
use Sys::Hostname;
use Time::HiRes qw/usleep/;
use Workflow::Server::UR;
use Workflow::Server::Hub;

class Workflow::Server::Remote {
    is_transactional => 0,
    id_by            => [ 'host', 'port' ],
    has              => [
        host => {
            is  => 'String',
            doc => 'Hostname to connect to Workflow::Server::UR process'
        },
        port => {
            is  => 'Integer',
            doc => 'Port number for the remote process'
        },
        _client => {}
    ]
};

### setting these signals to exit makes the guards run

$SIG{'HUP'} = sub {
    exit;
};

$SIG{'INT'} = sub {
    exit;
};

$SIG{'TERM'} = sub {
    exit;
};

sub launch {
    my $class = shift;

    croak 'exec is not an instance method' if ref($class);

    $class->set_signals;

    my $sl_g = $class->guard_lock('Simple');

    my $ur_port = $Workflow::Server::UR::port_number;
    while ( !$class->_is_port_available($ur_port) ) {
        $ur_port += 2;
    }
    my $hub_port = $Workflow::Server::Hub::port_number;
    while ( !$class->_is_port_available($hub_port) ) {
        $hub_port += 2;
    }

    local $ENV{'PERL5LIB'} = UR::Util::used_libs_perl5lib_prefix() . $ENV{'PERL5LIB'};

    my $hl_g = $class->guard_lock('Hub');
    my $ul_g = $class->guard_lock('UR');

    my $h = IPC::Run::start(
        [
            'workflow',   'server',
            '--type=hub', "--hub-port=$hub_port",
            "--ur-port=$ur_port"
        ]
    );
    my $h_g = guard { print "hg\n"; $h->kill_kill; $h->finish; };

    Workflow::Server->wait_for_lock( 'Hub', $h );
    $hl_g->cancel;

    my $u = IPC::Run::start(
        [
            'workflow',  'server',
            '--type=ur', "--hub-port=$hub_port",
            "--ur-port=$ur_port"
        ]
    );
    my $u_g = guard { print "ug\n"; $u->kill_kill; $u->finish; };

    Workflow::Server->wait_for_lock( 'UR', $u );
    $ul_g->cancel;

    Workflow::Server->unlock('Simple');
    $sl_g->cancel;

    ## servers use prctl PR_SET_PDEATHSIG SIGHUP, they dont need guards to die
    $class->restore_signals;

    my $self = $class->get(
        host => hostname(),
        port => $ur_port
    );

    return unless $self;

    if (wantarray) {
        return $self, [$u => $u_g, $h => $h_g];
    } else {
        $u_g->cancel;
        $h_g->cancel;

        return $self;
    }
}

sub end_child_servers {
    my ($self, $guards) = @_;

    $self->quit;

    my $t = 0; 
    while (1) {
        my $done = 0;
        foreach my $i (0,2) {
            if ($guards->[$i]->_running_kids) {
                $guards->[$i]->reap_nb;
            } else {
                $guards->[$i]->finish;
                eval { $guards->[$i+1]->cancel };
                $done++;
            }
        }

        if ($done == 2) {
            last;
        }

        if ($t > 50) {
            foreach my $i (1,3) {
                undef $guards->[$i];
            }

            last;
        }
        $t++;
        usleep 100000;
    }

    return 1;
}

our %OLD_SIGNALS = ();
sub set_signals {
    @OLD_SIGNALS{'HUP','INT','TERM'} = @SIG{'HUP','INT','TERM'};
    my $cb = sub {
        warn 'signalled exit';
        exit;
    };
    
    @SIG{'HUP','INT','TERM'} = ($cb,$cb,$cb);
}

sub restore_signals {
    foreach my $sig (keys %OLD_SIGNALS) {
        $SIG{$sig} = delete $OLD_SIGNALS{$sig};
    }
    return 1;
}

sub get {
    my $class = shift;

    return $class->SUPER::get(@_) || $class->create(@_);
}

sub create {
    my $class  = shift;
    my $params = $class->preprocess_params(@_);

    unless ( defined $params->{host} && defined $params->{port} ) {
        $class->error_message('host and port must be set');
        return undef;
    }

    my $poe = create_ikc_client(
        ip              => $params->{host},
        port            => $params->{port},
        timeout         => 1209600,
        connect_timeout => 5
    );
    if ( !$poe ) {
        $class->error_message(
            'Cannot connect: ' . POE::Component::IKC::ClientLite::error() );
        return undef;
    }

    my $self = $class->SUPER::create(@_);
    $self->_client($poe);

    return $self;
}

sub add_plan {
    my ( $self, $plan ) = @_;

    croak 'must supply a plan'
      unless defined $plan;

    my $xml;
    if ( ref($plan) ) {
        if ( ref($plan) eq 'GLOB' ) {

            # FILEHANDLE (i hope)
            $xml = '';
            while ( my $line = <$xml> ) {
                $xml .= $line;
            }
        } elsif ( UNIVERSAL::isa( $plan, 'Workflow::Operation' ) ) {

            # OBJECT
            $xml = $plan->save_to_xml;
        } else {
            croak 'plan was not filehandle, object or xml string';
        }
    } else {
        $xml = $plan;
    }

    my $plan_id = $self->_client->call( 'workflow/load', [$xml] )
      or croak $self->_client->error;

    return $plan_id;
}

sub simple_start {
    my ($self, $xml, $input ) = @_;
    
    my $response = $self->_client->post_respond('workflow/simple_start',[$xml,$input])
        or croak 'client error (unserializable input passed?): ' . $self->_client->error;
    
    return $response;
}

sub simple_resume {
    my ($self, $id) = @_;

    my $response = $self->_client->post_respond('workflow/simple_resume',[$id])
        or croak 'client error: ' . $self->_client->error;

    return $response;
}

sub start {
    my ( $self, $plan_id, $input ) = @_;

    #return $instance_id;
}

sub resume {
    my ( $self, $instrance_id ) = @_;

}

sub stop {
    my ( $self, $instance_id ) = @_;

}

sub quit {
    my ($self) = @_;

    $self->_client->post( 'workflow/quit', 1 );

    $self->delete;
}

sub loaded_instances {
    my ($self) = @_;

    my @ids = $self->_seval(
        q{
            my @instance = Workflow::Operation::Instance->is_loaded(parent_instance_id => undef);

            my @ids = ();
            foreach my $i (@instance) {
                if (defined $i->peer_instance_id && $i->peer_instance_id ne $i->id) {
                    next;
                }

                push @ids, $i->id;
            }
            return @ids;
        }
    );

    return @ids;
}

sub _seval {
    my $self = shift;
    my $code = shift;
    my @args = @_;

    my $wantlist = wantarray ? 1 : 0;

    my $result = $self->_client->call( "workflow/eval", [ $code, $wantlist, \@args ] );

    unless ($result) {
        confess 'internal error: ' . $self->_client->error;
    }

    unless ( ref($result) eq 'ARRAY' && scalar @$result == 2 ) {
        confess 'unexpected return type from workflow/eval: '
          . Data::Dumper->new( [$result], ['result'] )->Dump;
    }

    unless ( $result->[0] ) {

        confess 'server threw exception: ' . $result->[1];
    }

    if ($wantlist) {
        return @{ $result->[1] };
    } else {
        return $result->[1];
    }
}

sub delete {
    my ($self) = @_;

    $self->_client->disconnect;

    return $self->SUPER::delete(@_);
}

sub print_STDOUT {
    my ( $self, $s ) = @_;

    my $result =
      $self->_client->call( 'workflow/eval',
        [ q|print STDOUT q{| . $s . q|};|, 0 ] );

    return $result;
}

sub print_STDERR {
    my ( $self, $s ) = @_;

    my $result =
      $self->_client->call( 'workflow/eval',
        [ q|print STDERR q{| . $s . q|};|, 0 ] );

    return $result;
}

sub _is_port_available {
    my $port = shift;

    socket( TESTSOCK, PF_INET, SOCK_STREAM, 6 );
    setsockopt( TESTSOCK, SOL_SOCKET, SO_REUSEADDR, 1 );

    my $val = bind( TESTSOCK, sockaddr_in( $port, INADDR_ANY ) );

    shutdown( TESTSOCK, 2 );
    close(TESTSOCK);

    return 1 if $val;
    return 0;
}

sub guard_lock {
    my ( $class, $lockname ) = @_;

    Workflow::Server->lock($lockname);
    return guard { Workflow::Server->unlock($lockname); };
}

1;
