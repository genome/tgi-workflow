package Workflow::Server::Remote;

use strict;
use warnings;
# now loaded at run time
# Globally loading it in Genome.pm breaks debugging for lims Gtk2 apps.
#use POE::Component::IKC::ClientLite;

use Guard;
use IPC::Run;
use Socket;
use Sys::Hostname;
use Time::HiRes qw/usleep/;
use Workflow::Server::UR;
use Workflow::Server::Hub;

class Workflow::Server::Remote {
    is_transactional => 0,
    id_by            => ['host', 'port'],
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

sub get_or_create {
    my $class = shift;
    return $class->SUPER::get(@_) || $class->create(@_);
}

sub create {
    my $class = shift;
    my $params = { $class->define_boolexpr(@_)->normalize->params_list };

    unless(defined($params->{host}) and defined($params->{port})) {
        $class->error_message('host and port must be set');
        return;
    }

    _load_poe();
    my $poe = POE::Component::IKC::ClientLite::create_ikc_client(
        ip              => $params->{host},
        port            => $params->{port},
        timeout         => 60 * 60 * 24 * 7 * 4, # 4 weeks
        connect_timeout => 5
    );
    if(!$poe) {
        $class->error_message('Cannot connect: ' .
                POE::Component::IKC::ClientLite::error());
        return undef;
    }

    my $self = $class->SUPER::create(@_);
    $self->_client($poe);

    return $self;
}

sub launch {
    my $class = shift;

    Carp::croak 'launch is not an instance method' if ref($class);

    _load_poe();
    _set_signals();

    local $ENV{'PERL5LIB'} = UR::Util::used_libs_perl5lib_prefix() .
            $ENV{'PERL5LIB'};
    require File::Which;

    # This lock is to ensure that the ports we get are indeed available
    # When we get around to actually launching the servers.
    my $launch_guard = _guard_lock('Remote Launch');

    my $ur_port = 17001;
    while ( !_is_port_available($ur_port) ) {
        $ur_port += 2;
    }
    my $hub_port = 17000;
    while ( !_is_port_available($hub_port) ) {
        $hub_port += 2;
    }

    my ($h, $h_g) = _launch_remote_server('hub', 'Hub', $ur_port, $hub_port);
    my ($u, $u_g) = _launch_remote_server('ur', 'UR', $ur_port, $hub_port);
    my $processes = [$u, $h];
    my $guards = [$u_g, $h_g];

    Workflow::Server->unlock('Remote Launch');
    $launch_guard->cancel;

    ## servers use prctl PR_SET_PDEATHSIG SIGHUP, they dont need guards to die
    _restore_signals();

    my $self = $class->get_or_create(
        host => hostname(),
        port => $ur_port
    );

    if($self) {
        return $self, $processes, $guards;
    } else {
        return;
    }
}

sub simple_start {
    my ($self, $xml, $input ) = @_;

    my $response = $self->_client->post_respond('workflow/simple_start',
            [$xml, $input]);
    unless($response) {
        Carp::croak 'client error (unserializable input passed?): ' .
                $self->_client->error;
    }
    return $response;
}

sub simple_resume {
    my ($self, $id) = @_;

    my $response = $self->_client->post_respond('workflow/simple_resume',[$id])
            or Carp::croak 'client error: ' . $self->_client->error;
    return $response;
}

sub end_child_servers {
    my ($self, $processes, $guards, $max_attempts) = @_;
    $max_attempts = $max_attempts || 50;

    $self->_quit();

    my %process_pairs;
    my $num_processes = scalar(@{$processes});
    for my $i (0..$num_processes-1) {
        $process_pairs{$i} = [shift @{$processes}, shift @{$guards}];
    }
    for my $t (1..$max_attempts) {
        for my $i (keys %process_pairs) {
            my $succeeded = _attempt_finish(@{$process_pairs{$i}});
            if($succeeded) {
                delete $process_pairs{$i};
            }
        }
        if(keys %process_pairs) {
            usleep 100_000;
        }
    }
    return 1;
}

sub _launch_remote_server {
    my ($type, $name, $ur_port, $hub_port) = @_;

    # It appears that this lock is to ensure that we wait until the server is
    # up before continuing.
    my $guard = _guard_lock($name);

    my $workflow_cmd = File::Which::which('workflow');
    my $process = IPC::Run::start(
            [
            $^X, $workflow_cmd,  'server',
            "--type=$type", "--hub-port=$hub_port",
            "--ur-port=$ur_port"
            ]
    );
    my $process_guard = guard { $process->kill_kill; $process->finish; };
    Workflow::Server->wait_for_lock($name, $process);

    $guard->cancel();
    return $process, $process_guard;
}

sub _attempt_finish {
    my ($process, $guard) = @_;

    if($process->_running_kids) {
        $process->reap_nb();
        return 0;
    } else {
        $process->finish();
        eval { $guard->cancel() };
        return 1;
    }
}

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

my $poe_loaded = 0;
sub _load_poe {
    return if $poe_loaded;

    if($ENV{PERL5DB}) {
        warn "Debugger detected.  The workflow engine may trigger runaway debugging in ptkdb...\n";
        warn "Use console debugger.\n";
        for my $mod (qw/Workflow::Server::Remote/) {
            warn "\t$mod...\n";
            eval "use $mod";
            die $@ if $@;
        }
        warn "Close any extra debug windows which may have been created by the POE engine.\n";
    }

    eval "use POE::Component::IKC::ClientLite";
    die $@ if $@;
    $poe_loaded=1;
}

our %OLD_SIGNALS = ();
sub _set_signals {
    @OLD_SIGNALS{'HUP','INT','TERM'} = @SIG{'HUP','INT','TERM'};
    my $cb = sub {
        warn 'signalled exit';
        exit;
    };

    @SIG{'HUP','INT','TERM'} = ($cb,$cb,$cb);
}

sub _restore_signals {
    foreach my $sig (keys %OLD_SIGNALS) {
        $SIG{$sig} = delete $OLD_SIGNALS{$sig};
    }
    return 1;
}

sub _quit {
    my ($self) = @_;

    $self->_client->post( 'workflow/quit', 1 );
    $self->_client->disconnect;
    return $self->SUPER::delete(@_);
}

sub _is_port_available {
    my $port = shift;

    socket(TESTSOCK, PF_INET, SOCK_STREAM, 6);
    setsockopt(TESTSOCK, SOL_SOCKET, SO_REUSEADDR, 1);

    my $val = bind(TESTSOCK, sockaddr_in($port, INADDR_ANY));

    shutdown(TESTSOCK, 2);
    close(TESTSOCK);

    return 1 if $val;
    return 0;
}

sub _guard_lock {
    my ($lockname) = @_;

    Workflow::Server->lock($lockname);
    return guard { Workflow::Server->unlock($lockname); };
}

1;
