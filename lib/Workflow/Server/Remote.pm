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
use Log::Log4perl qw(:easy);
require Workflow::Server;
require File::Temp;
require POSIX;

BEGIN {
    if(defined $ENV{WF_TRACE_REMOTE}) {
        Log::Log4perl->easy_init($DEBUG);
    } else {
        Log::Log4perl->easy_init($ERROR);
    }
};

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

    DEBUG "remote get_or_create";
    return $class->SUPER::get(@_) || $class->create(@_);
}

sub create {
    my $class = shift;
    my $params = { $class->define_boolexpr(@_)->normalize->params_list };

    DEBUG "remote create";
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
    DEBUG sprintf("Connected IKC::ClientLite to hub (%s:%s)",
            $params->{host},
            $params->{port});

    return $self;
}

sub _make_fifo_for_location_communication {
    my $fifo_dir = File::Temp::tempdir(CLEANUP => 1);
    my $fifo_name = join('/', $fifo_dir, 'hub_location');

    unless (POSIX::mkfifo($fifo_name, 0600) == 0) {
        Carp::confess(sprintf(
                "Could not create fifo %s for location communication.",
                $fifo_name));
    }

    return $fifo_name;
}

sub launch {
    my $class = shift;

    Carp::croak 'launch is not an instance method' if ref($class);

    _load_poe();
    _set_signals();

    local $ENV{'PERL5LIB'} = UR::Util::used_libs_perl5lib_prefix() .
            $ENV{'PERL5LIB'};
    require File::Which;

    my $hub_fifo = _make_fifo_for_location_communication();

    DEBUG "remote Launching hub server";
    my ($h, $h_g) = _launch_hub_server($hub_fifo);

    # block to get HUB port
    DEBUG "remote Waiting on hub to start up and announce it's location";
    my ($hub_hostname, $hub_port) =
            Workflow::Server::get_location_from_fifo($hub_fifo);
    DEBUG "remote Hub server at $hub_hostname:$hub_port";

    DEBUG "remote Launching ur server";
    my ($u, $u_g) = _launch_ur_server($hub_hostname, $hub_port);

    my $processes = [$u, $h];
    my $guards = [$u_g, $h_g];

    ## servers use prctl PR_SET_PDEATHSIG SIGHUP, they dont need guards to die
    _restore_signals();

    my $self = $class->get_or_create(
        host => $hub_hostname,
        port => $hub_port
    );

    if($self) {
        return $self, $processes, $guards;
    } else {
        return;
    }
}

sub start {
    my ($self, $xml, $input) = @_;

    my $response = $self->_client->post_respond('passthru/start_ur',
            [$xml, $input]);
    unless($response) {
        Carp::croak 'client error (unserializable input passed?): ' .
                $self->_client->error;
    }
    return $response;
}

sub resume {
    my ($self, $id) = @_;

    my $response = $self->_client->post_respond('passthru/resume_ur',[$id])
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

sub _launch_hub_server {
    my ($announce_location_fifo) = @_;

    my $workflow_cmd = File::Which::which('workflow');
    my $process = IPC::Run::start(
            [
            $^X, $workflow_cmd,  'start-hub',
            "--announce-location-fifo=$announce_location_fifo",
            ]
    );
    my $process_guard = guard { $process->kill_kill; $process->finish; };

    return $process, $process_guard;
}


sub _launch_ur_server {
    my ($hub_hostname, $hub_port) = @_;

    my $workflow_cmd = File::Which::which('workflow');
    my $process = IPC::Run::start(
            [
            $^X, $workflow_cmd,  'start-ur',
            "--hub-hostname=$hub_hostname",
            "--hub-port=$hub_port",
            ]
    );
    my $process_guard = guard { $process->kill_kill; $process->finish; };

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
    eval "use POE::Component::IKC";
    DEBUG "Loaded POE::Component::IKC version " .
            $POE::Component::IKC::VERSION;
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

    $self->_client->post( 'passthru/quit_ur', 1);
    $self->_client->disconnect();
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
