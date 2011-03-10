package Cord::Metrics::Usrbintime;

use base qw(Cord::Metrics);

use strict;
use warnings;

sub run {
  my $self = shift;
  my $cmd = shift;
  my $args = shift;

  die "/usr/bin/time is not present and executable" if (! -x "/usr/bin/time");

  # FIXME: This isn't going to work.
  my $timecmd = '/usr/bin/time -f "command: %C\ntime.user: %U\ntime.sys: %S\ntime.wall: %e\ncpu: %P\nmem.avg.shared.text: %X\nmem.avg.unshared.data: %D\nmem.avg.stack: %p\nmem.avg.total: %K\nmem.max.resident: %M\nmem.avg.resident: %t\nmem.maj.fault: %F\nmem.min.fault: %R\ncontext.vol: %w\ncontext.inv: %c\nswaps: %W\nfs.inputs: %I\nfs.outputs: %O\nsocket.sent: %s\nsocket.rcvd: %r\nsignals.delivered: %k\npage.size: %Z\nexit.status: %x\n"' . " -o $self->{metrics}";

  return AnyEvent::Util::run_cmd(
    "$timecmd $cmd $args",
    ">"  => $self->{output},
    "2>" => $self->{errors},
  );
}

1;
