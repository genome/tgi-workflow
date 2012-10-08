package POE::API::Peek;

=head1 NAME

POE::API::Peek - Peek into the internals of a running POE environment

=head1 DESCRIPTION

POE::API::Peek extends the POE::Kernel interface to provide clean access
to Kernel internals in a cross-version compatible manner. Other
calculated data is also available.

My intention is to provide massive amounts of internal data for use in
POE debugging. 

=head1 WARNING

B<This version of this module is certified against POE version 1.0001 and 
above. It will fail on any other POE version.>

B<Further, this module requires perl v5.6.1 or above.>

=head1 METHODS

=cut

use 5.006001;
use warnings;
use strict;

our $VERSION = '2.15';

BEGIN {
	use POE;
	my $ver = $POE::VERSION;
	$ver =~ s/_.+$//;
	if($ver < '1.0001') {
		die(__PACKAGE__." is only certified for POE version 1.0001 and up and you are running POE version " . $ver . ". Check CPAN for an appropriate version of ".__PACKAGE__.".");
	}
}

use POE;
use Devel::Size qw(total_size);
$Devel::Size::warn = 0;

# new {{{

=head2 new

  my $api = POE::API::Peek->new();

Returns a blessed reference. Takes no parameters.

=cut

sub new { return bless {}, shift; }

# }}}

# id() {{{

=head2 id

  my $foo = $api->id();

Obtain the unique id for the kernel. Takes no parameters. Returns a
scalar containing a string.

=cut

sub id { return $poe_kernel->ID }

# }}}

# Kernel fun {{{

=head1 KERNEL UTILITIES

=cut

# is_kernel_running {{{

=head2 is_kernel_running

  if($api->is_kernel_running) {
      # do stuff...
  }

Tell if the POE Kernel is running and active. Returns 1 if the Kernel is 
running and 0 if it is not.

=cut

sub is_kernel_running {
	my $kr_run_warning = ${ $poe_kernel->[ POE::Kernel::KR_RUN() ] };

	if($kr_run_warning |= POE::Kernel::KR_RUN_CALLED()) {
		return 1;
	} else {
		return 0;
	}
}

#}}}

# active_event {{{

=head2 active_event

  my $event = $api->active_event();

Get the active event name. Returns a string containing the event name.

=cut

sub active_event { 
	return ${ $poe_kernel->[ POE::Kernel::KR_ACTIVE_EVENT() ] }; 
}

#}}}

# kernel_memory_size {{{

=head2 kernel_memory_size

  my $size = $api->kernel_memory_size();

Get the memory footprint of the kernel and consequently the entire POE environment.
See the Devel::Size documentation for several caveats involved in this metric.

=cut

sub kernel_memory_size {
	return total_size($poe_kernel);
}
# }}}

# event_list {{{

=head2 event_list

  my $events = $api->event_list();

Gets the list of events for the whole POE environment. Returns a hash
with the session IDs as the keys and a list of events as the 
values.

=cut

sub event_list {
	my $self = shift;
   
	my %events;
	foreach my $session_ref (keys %{ $poe_kernel->[ &POE::Kernel::KR_SESSIONS() ] }) {
		my $session = $poe_kernel->[ &POE::Kernel::KR_SESSIONS() ]->{ $session_ref }->[ &POE::Kernel::SS_SESSION() ];
		next if $session->isa('POE::Kernel');
		my $id = $session->ID;

		my @events = sort keys %{ $session->[ &POE::Session::SE_STATES() ] };

		$events{ $id } = \@events;
	}

	return \%events;
}
# }}}

# which_loop {{{

=head2 which_loop

  my $loop_name = $api->which_loop();

Tell which Loop POE has decided to use. Returns the string name of the Loop
module.

=cut

sub which_loop {
	return POE::Kernel::poe_kernel_loop();
}

#}}}


# }}}

# Session fun {{{

=head1 SESSION UTILITIES

=cut

# current_session {{{

=head2 current_session

  my $foo = $api->current_session();

Get the POE::Session object for the currently active session. Takes no
parameters. Returns a scalar containing a reference.

=cut

# the value of KR_ACTIVE_SESSION is a ref to a scalar. so we deref it before 
# handing it to the user.

sub current_session { return ${ $poe_kernel->[POE::Kernel::KR_ACTIVE_SESSION] } }

# }}}

# get_session_children {{{

=head2 get_session_children

    my @children = $api->get_session_children($session);
    my @children = $api->get_session_children();

Get the children (if any) for a given session. Takes one optional
parameter, a POE::Session object. If this parameter is not provided, the
method defaults to the currently active session. Returns a list of
POE::Session objects.

=cut

sub get_session_children {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_ses_get_children($session);
}
# }}}

# is_session_child {{{

=head2 is_session_child

  if($api->is_session_child($parent, $session)) { }
  if($api->is_session_child($parent)) { }

Determine if POE::Session A is a child of POE::Session B. Takes one
mandatory parameter, a POE::Session object which is the potential parent
session this method will interrogate. Takes one optional parameter, a
POE::Session object which is the session whose parentage this method
will determine. If this parameter is not specified, it will default to
the currently active session. Returns a boolean. 

=cut

sub is_session_child {
	my $self = shift;
	my $parent = shift or return undef;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_ses_is_child($parent, $session);
}
# }}}

# get_session_parent {{{

=head2 get_session_parent

    my $parent = $api->get_session_parent($session);
    my $parent = $api->get_session_parent();

Get the parent for a given session. Takes one optional parameter, a
POE::Session object. If this parameter is not provided, the method defaults to
the currently active session. Returns a POE::Session object.

=cut

sub get_session_parent {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_ses_get_parent($session);
}
# }}}


# resolve_session_to_ref {{{

=head2 resolve_session_to_ref

  my $session = $api->resolve_session_to_ref($session_id);
  my $session = $api->resolve_session_to_ref();

Obtain a reference to a session given its ID. Takes one optional
parameter, a POE::Session ID. If this parameter is not specified, it
will default to the currently active session. Returns a reference to a
POE::Session object on success; undef on failure.

=cut

sub resolve_session_to_ref {
	my $self = shift;
	my $id = shift || $self->current_session()->ID;
	return $poe_kernel->_data_sid_resolve($id);
}
# }}}

# resolve_session_to_id {{{

=head2 resolve_session_to_id

  my $session_id = $api->resolve_session_to_id($session);
  my $session_id = $api->resolve_session_to_id();

Obtain the session id for a given POE::Session object. Takes one
optional parameter, a POE::Session object. If this parameter is not
specified, it will default to the currently active session. Returns an
integer on success and undef on failure.

=cut

sub resolve_session_to_id {
    my $self = shift;
    my $session = shift || $self->current_session();
    return $poe_kernel->_data_ses_resolve_to_id($session);
}
# }}}

# get_session_refcount {{{

=head2 get_session_refcount

  my $count = $api->get_session_refcount($session);
  my $count = $api->get_session_refcount();

Obtain the reference count for a given POE::Session. Takes one optional
parameter, a POE::Session object. If this parameter is not specified, it
will default to the currently active session. Returns an integer.

=cut

sub get_session_refcount {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_ses_refcount($session);
}
# }}}

# session_count {{{

=head2 session_count

  my $count = $api->session_count();

Obtain a count of how many sessions exist. Takes no parameters. Returns
an integer.

Note: for various reasons, the Kernel counts as a session. 

=cut

sub session_count {
	return $poe_kernel->_data_ses_count();
}
# }}}

# session_list {{{

=head2 session_list

  my @sessions = $api->session_list();

Obtain a list of all the sessions that exist. Takes no parameters.
Returns a list populated with POE::Session objects.

Note: While the Kernel counts as a session, it has been extracted
from this list.

=cut

sub session_list {
	my @sessions;
	my $kr_sessions = $POE::Kernel::poe_kernel->[POE::Kernel::KR_SESSIONS];
	foreach my $key ( keys %$kr_sessions ) {
		next if $key =~ /POE::Kernel/;
		push @sessions, $kr_sessions->{$key}->[0];
	}
	return @sessions;
}
# }}}

# session_memory_size {{{

=pod

=head2 session_memory_size

  my $size = $api->session_memory_size();
  my $size = $api->session_memory_size($session);

Get the memory footprint of a session. If no session is provided, the current
session is used. See the Devel::Size documentation for several caveats 
involved in this metric.

=cut

sub session_memory_size {
	my $self = shift;
	my $session = shift || $self->current_session();
	return total_size($session);
}
# }}}}

# session_event_list {{{

=head2 session_event_list

  my @events = $api->session_event_list();
  my $events = $api->session_event_list();
  my @events = $api->session_event_list($session);
  my $events = $api->session_event_list($session);

Get the list of events for a session. If no session is provided, the current
session is used.

=cut

sub session_event_list {
	my $self = shift;
	my $session = shift || $self->current_session();
	my @events = sort keys %{ $session->[ &POE::Session::SE_STATES() ] };

	if(wantarray) {
		return @events;
	} else {
		return \@events;
	}
}
# }}}

# }}}

# Alias fun {{{

=head1 ALIAS UTILITIES

=cut

# resolve_alias {{{

=head2 resolve_alias

  my $session = $api->resolve_alias($session_alias);

Resolve a session alias into a POE::Session object. Takes one mandatory
parameter, a session alias. Returns a POE::Session object on success or
undef on failure.

=cut

sub resolve_alias {
	my $self = shift;
	my $alias = shift or return undef;
	return $poe_kernel->_data_alias_resolve($alias);
}
# }}}

# session_alias_list {{{

=head2 session_alias_list

  my @aliases = $api->session_alias_list($session);
  my @aliases = $api->session_alias_list();

Obtain a list of aliases for a POE::Session object. Takes one optional
parameter, a POE::Session object. If this parameter is not specified, it
will default to the currently active session. Returns a list of strings.

=cut

sub session_alias_list {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_alias_list($session);
}
# }}}

# session_alias_count {{{

=head2 session_alias_count

  my $count = $api->session_alias_count($session);
  my $count = $api->session_alias_count();

Obtain the count of how many aliases a session has. Takes one optional
parameter, a POE::Session object. If this parameter is not specified, it
will default to the currently active session. Returns an integer.

=cut

sub session_alias_count {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_alias_count_ses($session);
}
# }}}

# session_id_loggable {{{

=head2 session_id_loggable

    my $str = $api->session_id_loggable($session);
    my $str = $api->session_id_loggable();

Obtain a loggable version of a session id. Takes one optional parameter,
a POE::Session object. If this parameter is not specified, it will
default to the currently active session. Returns a string.

=cut

sub session_id_loggable {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_alias_loggable($session);
}
# }}}

# }}}

# Event fun {{{

=head1 EVENT UTILITIES

=cut

# event_count_to {{{

=head2 event_count_to

  my $count = $api->event_count_to($session);
  my $count = $api->event_count_to();

Get the number of events heading toward a particular session. Takes one
parameter, a POE::Session object. if none is provided, defaults to the
current session. Returns an integer.

=cut

sub event_count_to {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_ev_get_count_to($session);    
}
#}}}

# event_count_from {{{

=head2 event_count_from

  my $count = $api->event_count_from($session);
  my $count = $api->event_count_from();

Get the number of events heading out from a particular session. Takes one
parameter, a POE::Session object. If non is provided, defaults to the 
current session. Return an integer.

=cut

sub event_count_from {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_ev_get_count_from($session);    
}

#}}}

# event_queue {{{

=head2 event_queue

  my $foo = $api->event_queue();

Access the internal event queue. Takes no parameters. Returns a scalar
containing a reference to a POE::Queue::Array object.

=cut

sub event_queue { return $poe_kernel->[POE::Kernel::KR_QUEUE] }

# }}}

# event_queue_dump {{{

=head2 event_queue_dump
    
  my @queue = $api->event_queue_dump();

Dump the contents of the event queue in a nice understandable fashion.  Takes no
parameters. Returns a list of queue items. Each item is a hash containing the
following entries:

=over 4

=item * ID 

The id number that POE's queue identifies this entry as.

=item * index

The index into the POE::Queue::Array which holds this entry.

=item * priority

The priority level this entry has.

=item * event

The name of this event

=item * source

What caused this event. Usually a POE::Session.

=item * destination

Where this event is headed. Usually a POE::Session.

=item * type

The type of event this is. May have the value User, _start, _stop, _signal,
_garbage_collect, _parent, _child, _sigchld_poll, Alarm, File Activity, or
Unknown. 

=back

=cut

sub event_queue_dump { 
	my $self = shift;
	my $queue = $self->event_queue;
	my @happy_queue;
	my @queue = $queue->peek_items(sub { return 1; });

	my $i = 0;
	foreach my $qitem (@queue) {
		my $item = {};
		my ($priority, $id, $payload) = @$qitem;
		 
		$item->{ID} = $id;
		$item->{index} = $i++;
		$item->{priority} = $priority; 

		my $ev_name = $payload->[POE::Kernel::EV_NAME()];
		$item->{event} = $ev_name;
		$item->{source} = $payload->[POE::Kernel::EV_SOURCE];
		$item->{destination} = $payload->[POE::Kernel::EV_SESSION];

		my $type = $payload->[POE::Kernel::EV_TYPE()];
		my $type_str;
		if ($type & POE::Kernel::ET_START()) {
			$type_str = '_start';
		} elsif ($type & POE::Kernel::ET_STOP()) {
			$type_str = '_stop';
		} elsif ($type & POE::Kernel::ET_SIGNAL()) {
			$type_str = '_signal';
		} elsif ($type & POE::Kernel::ET_GC()) {
			$type_str = '_garbage_collect';
		} elsif ($type & POE::Kernel::ET_PARENT()) {
			$type_str = '_parent';
		} elsif ($type & POE::Kernel::ET_CHILD()) {
			$type_str = '_child';
		} elsif ($type & POE::Kernel::ET_SCPOLL()) {
			$type_str = '_sigchld_poll';
		} elsif ($type & POE::Kernel::ET_ALARM()) {
			$type_str = 'Alarm';
		} elsif ($type & POE::Kernel::ET_SELECT()) {
			$type_str = 'File Activity';
		} else {
			my $ver = $POE::VERSION;
			$ver =~ s/_.+$//;
			if($ver <= 0.27) {
				if($type & POE::Kernel::ET_USER()) {
					$type_str = 'User';
				} else {
					$type_str = 'Unknown';
				}
			} else {
				if($type & POE::Kernel::ET_POST()) {
					$type_str = 'User';
				} elsif ($type & POE::Kernel::ET_CALL()) {
					$type_str = 'User (not enqueued)';
				} else {
					$type_str = 'Unknown';
				}
			}
		}
        
		$item->{type} = $type_str;
		push @happy_queue, $item;
	}

	return @happy_queue;
} #}}}



# }}}

# Extref fun {{{

=head1 EXTREF UTILITIES

=cut

# extref_count {{{

=head2 extref_count

  my $count = $api->extref_count();

Obtain a count of sessions with extra references. Takes no parameters.
Returns an integer.

=cut

sub extref_count {
	return $poe_kernel->_data_extref_count();
}
# }}}

# get_session_extref_count {{{

=head2 get_session_extref_count

  my $count = $api->get_session_extref_count($session);
  my $count = $api->get_session_extref_count();

Obtain the number of extra references a session has. Takes one optional
parameter, a POE::Session object. If this parameter is not specified, it
will default to the currently active session. Returns an integer.

=cut

sub get_session_extref_count {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_extref_count_ses($session);
}
# }}}

# }}}

# Filehandles Fun {{{

=head1 FILEHANDLE UTILITIES

=cut

# is_handle_tracked {{{

=head2 is_handle_tracked

  if($api->is_handle_tracked($handle, $mode)) { }

Determine if POE is tracking a handle. Takes two mandatory parameters, a
filehandle and a mode indicator. Returns a boolean.

=cut

sub is_handle_tracked {
	my($self, $handle, $mode) = @_;
	return $poe_kernel->_data_handle_is_good($handle, $mode);
}
# }}}

# handle_count {{{

=head2 handle_count

  my $count = $api->handle_count();

Obtain a count of how many handles POE is tracking. Takes no parameters.
Returns an integer.

=cut

sub handle_count {
	return $poe_kernel->_data_handle_count();
}
# }}}

# session_handle_count {{{

=head2 session_handle_count 

  my $count = $api->session_handle_count($session);
  my $count = $api->session_handle_count();

Obtain a count of the active handles for a given session. Takes one
optional parameter, a POE::Session object. If this parameter is not
supplied, it will default to the currently active session.

=cut

sub session_handle_count {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_handle_count_ses($session);
}
# }}}

# }}}

# Signals Fun {{{

=head1 SIGNAL UTILITIES

=cut

# get_safe_signals {{{

=head2 get_safe_signals

  my @safe_signals = $api->get_safe_signals();

Obtain a list of signals which it is safe for POE to manipulate. Takes
no parameters. Returns a list of strings.

=cut

sub get_safe_signals {
	return $poe_kernel->_data_sig_get_safe_signals();
}
# }}}

# get_signal_type {{{

=head2 get_signal_type

  my $type = $api->get_signal_type($signal_name);

Figure out which type of signal this is. Signals can be one of three
types, BENIGN, TERMINAL, NONMASKABLE. The type value returned here,
corresponds to subroutine constants SIGTYPE_BENIGN, SIGTYPE_TERMINAL,
and SIGTYPE_NONMASKABLE in POE::Kernel's namespace. Takes one mandatory
parameter, a signal name.

=cut

sub get_signal_type {
	my $self = shift;
	my $sig = shift or return undef;
	return $poe_kernel->_data_sig_type($sig);
}
# }}}

# is_signal_watched {{{

=head2 is_signal_watched

  if($api->is_signal_watched($signal_name)) { }

Determine if a signal is being explicitly watched. Takes one mandatory
parameter, a signal name. Returns a boolean.

=cut

sub is_signal_watched {
	my $self = shift;
	my $sig = shift or return undef;
	return $poe_kernel->_data_sig_explicitly_watched($sig);
}
# }}}

# signals_watched_by_session {{{

=head2 signals_watched_by_session

  my %signals = $api->signals_watched_by_session($session);
  my %signals = $api->signals_watched_by_session();

Get the signals watched by a session and the events they generate. Takes
one optional parameter, a POE::Session object. If this parameter is not
supplied, it will default to the currently active session. Returns a
hash, with a signal name as the key and the event the session generates
as the value.

=cut

sub signals_watched_by_session {
	my $self = shift;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_sig_watched_by_session($session);
}
# }}}

# signal_watchers {{{

=head2 signal_watchers

  my %watchers = $api->signal_watchers($signal_name);

Get a list of the sessions watching a particular signal. Takes one
mandatory parameter, a signal name. Returns a hash, keyed by session
reference with an event name as the value.

=cut

sub signal_watchers {
	my $self = shift;
	my $sig = shift or return undef;
	return $poe_kernel->_data_sig_watchers($sig);
}
# }}}

# is_signal_watched_by_session {{{

=head2 is_signal_watched_by_session

  if($api->is_signal_watched_by_session($signal_name, $session)) { }
  if($api->is_signal_watched_by_session($signal_name)) { }

Determine if a given session is explicitly watching a signal. Takes one
mandatory parameter, a signal name. Takes one optional parameter, a
POE::Session object. If this parameter is not provided, it will default
to the currently active session. Returns a boolean.

=cut

sub is_signal_watched_by_session {
	my $self = shift;
	my $signal = shift or return undef;
	my $session = shift || $self->current_session();
	return $poe_kernel->_data_sig_is_watched_by_session($signal, $session);
}
# }}}

# }}}


1;
__END__

=pod

=head1 AUTHORS

=over 4

=item Matt Cashner (sungo@pobox.com)

=item Yuval Kogman (nothingmuch@woobling.org)

=back


=head1 LICENSE

=over 4

=item Copyright (c) 2003 - 2008, Matt Cashner. 

=item Copyright (c) 2008, Yuval Kogman

=back

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

=over 4

=item * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.  

=item * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

=item * Neither the name of Matt Cashner nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

=back

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

# sungo // vim: ts=4 sw=4 noet
