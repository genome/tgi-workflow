package Workflow::Job::Lsf;

use strict;
use Workflow;
use Date::Parse;

class Workflow::Job::Lsf {
    is              => 'Workflow::Job',
    attributes_have => [
        populate_from => {
            is          => 'String',
            is_optional => 1
        }
    ],
    has_many => [
        events => {
            is => 'Workflow::Job::Event::Lsf'
            ,    ## specifying this manually makes default views better
            reverse_as => 'job'
        }
    ],
    has => [
        __populated => {
            is    => 'Boolean',
            value => 0
        },
        status       => { populate_from => 'Status' },
        user         => { populate_from => 'User' },
        queue        => { populate_from => 'Queue' },
        command      => { populate_from => 'Command' },
        job_name     => { populate_from => 'Job Name' },
        project      => { populate_from => 'Project' },
        job_group    => { populate_from => 'Job Group' },
        job_priority => { populate_from => 'Job Priority' }
    ]
};

# _load in our parent class calls this
sub _create_object {
    my ( $class, $rule ) = @_;
    my @obj = $class->SUPER::_create_object($rule);

    my %job_ids = map { $_->job_id => $_ } @obj;

    open my $f, 'bjobs -l ' . join( ' ', keys %job_ids ) . ' |';
    readline $f;
    my $buffer = [ scalar( readline($f) ) ];

    while ( my $jobhash = $class->__read_and_parse_one_job( $buffer, $f ) ) {
        next unless exists $job_ids{ $jobhash->{'Job'} };
        $job_ids{ $jobhash->{'Job'} }->__populate($jobhash);
    }

    close $f;

    return @obj;
}

sub __populate {
    my $self  = shift;
    my $jhash = shift;

    return if $self->__populated;

    my @property_meta = $self->get_class_object->all_property_metas();
    my %map = map { $_->property_name => $_->{'populate_from'} } @property_meta;

    while ( my ( $prop, $key ) = each %map ) {
        next unless $key;
        $self->$prop( delete $jhash->{$key} );
    }

    my $events = delete $jhash->{_events_};
    foreach my $earray (@$events) {
        my $time = str2time( $earray->[0] );
        my $e = $self->add_event( time => $time );

        $e->__populate( $earray->[1] );
    }

    $self->{__bare} = $jhash;

    $self->__populated(1);
}

sub __read_and_parse_one_job {
    my @lines = shift->__read_one_job(@_);
    return unless @lines;

    my $spool = join( '', @lines );

    # this regex nukes the indentation and line feed
    $spool =~ s/\s{22}//gm;

    my @eventlines = split( /\n/, $spool );
    my %jobinfo = ();

    my $jobinfoline = shift @eventlines;
    if ( defined $jobinfoline ) {

        # sometimes the prior regex nukes the white space between Key <Value>
        $jobinfoline =~ s/(?<!\s{1})</ </g;
        $jobinfoline =~ s/>,(?!\s{1})/>, /g;

        # parse out a line such as
        # Key <Value>, Key <Value>, Key <Value>
        while ( $jobinfoline =~
            /(?:^|(?<=,\s{1}))(.+?)(?:\s+<(.*?)>)?(?=(?:$|;|,))/g )
        {
            $jobinfo{$1} = $2;
        }
    }

    $jobinfo{_events_} = [];
    foreach my $el (@eventlines) {
        if ( $el =~
/^(Sun|Mon|Tue|Wed|Thu|Fri|Sat) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s{1,2}(\d{1,2})\s{1,2}(\d{1,2}):(\d{2}):(\d{2}):/
          )
        {

            $el =~ s/(?<!\s{1})</ </g;
            $el =~ s/>,(?!\s{1})/>, /g;

            my $time = substr( $el, 0, 21, '' );
            substr( $time, -2, 2, '' );

            # see if we really got the time string
            if ( $time !~ /\w{3} \w{3}\s+\d{1,2}\s+\d{1,2}:\d{2}:\d{2}/ ) {

                # there's stuff we dont care about at the bottom, just skip it
                next;
            }

            my $desc = {};
            while ( $el =~
/(?:^|(?<=,\s{1}))(.+?)(?:\s+<(.*?)>(?:\s+(.*?))?)?(?=(?:$|;|,))/g
              )
            {
                if ( defined $3 ) {
                    $desc->{$1} = [ $2, $3 ];
                } else {
                    $desc->{$1} = $2;
                }
            }
            push @{ $jobinfo{_events_} }, [ $time, $desc ];

        }
    }
    return \%jobinfo;
}

sub __read_one_job {
    my $class  = shift;
    my $buffer = shift;
    my $fh     = shift;

    while (1) {
        my $line = readline($fh);
        push @$buffer, $line;

        if ( defined $line && $line =~ /^Job \</ ) {
            last;
        } elsif ( !defined $line ) {
            last;
        }
    }
    my @jl = splice( @$buffer, 0, -1 );
    if ( defined $jl[0] ) {
        return @jl;
    } else {
        return;
    }

}

1;
