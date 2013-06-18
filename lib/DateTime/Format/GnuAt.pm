package DateTime::Format::GnuAt;

our $VERSION = '0.01';

use strict;
use warnings;
use Carp;
use DateTime;

my @periods = qw(minute hour day week month year);
my $period_re = join '|', @periods;
$period_re = qr/(?:$period_re)\b/i;

my (%month, %wday);
my @months = qw(january february march april may june july august
                september october november december);
@month{map substr($_, 0, 3), @months} = (1..12);

my @wdays = qw(monday tuesday wednesday thursday friday saturday sunday);
@wday{map substr($_, 0, 3), @wdays} = (1..7);

sub _make_alternation_re {
    my $re = join '|',
        map {
            substr($_, 0, 3) . (length > 3 ? '(?:' . substr($_, 3) . ')?' : '')
        } @_;
    return qr/(?:$re)\b/i;
}

my $month_re = _make_alternation_re(@months);
my $wday_re  = _make_alternation_re(@wdays );

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
}

sub _reset {
    my ($self, $opts) = @_;
    %$self = ();
    $self->{now} = delete($opts->{now}) // DateTime->now(time_zone => 'local');
}

sub parse_datetime {
    my ($self, $spec, %opts) = @_;

    $self->_reset(\%opts);

    for ($spec) {
        /^\s*/gc;

        if ($self->_parse_spec_base()) {
            /\G\s*/gc;
            $self->_parse_inc_or_dec;
        }
        /\G\s*/gc;
        /\G\S/gc and croak "invalid date-time specification '$spec'";
    }

    $self->{date}->set_time_zone('UTC');

    warn "datetime: $self->{date}\n";
}

sub _parse_spec_base {
    my $self = shift;
    if ($self->_parse_date) {
        return 1;
    }
    elsif ($self->_parse_time) {
        my $pos = pos;
        unless (/\G\s+/gc and $self->_parse_date) {
            pos = $pos;
            my $base = $self->{now};
            my $base_hour = $base->hour;
            my $base_min = $base->min;
            if ( ( $base_hour > $self->{hour} ) or
                 ( ( $base_hour == $self->{hour} ) and
                   ( $base_min >= $self->{min} ) ) ) {
                $base = $base->add(days => 1);
            }
            $self->{date} = $base;
        }

        $self->{date}->set(hour => $self->{hour},
                           minute => $self->{min},
                           second => 0);


        return 1;
    }
    return
}

sub _parse_date {
    my $self = shift;

    my $now = $self->{now};

    if (/\G($month_re)\s+(\d\d?)(?:(?:\s+|\s*,\s*)(\d\d(?:\d\d)?))?/gco) {
        # month_name day_number
        # month_name day_number year_number
        # month_name day_number ',' year_number
        @{$self}{qw(month_name day year)} = ($1, $2, $3);
    }
    elsif (/\G(?:next\s+)?($wday_re)/gcio) {
        # day_of_week
        $self->{wday_name} = $1;
        my $wday = $self->{wday} = $wday{lc substr $1, 0, 3};
        my $delta = $wday - $now->day_of_week;
        $delta += 7 if $delta <= 0;
        $self->{date} = $now->add(days => $delta);
        return 1;
    }
    elsif (/\Gtoday\b/gci) {
        # TODAY
        $self->{today} = 1;
        $self->{date} = $now;
        return 1;
    }
    elsif (/\Gtomorrow\b/gci) {
        # TOMORROW
        $self->{tomorrow} = 1;
        $self->{date} = $now->add(days => 1);
        return 1;
    }
    elsif (/\G(\d\d?)\.(\d\d?)\.(\d\d(?:\d\d)?)\b/gc) {
        # DOTTEDDATE (dd.mm.[cc]yy)
        @{$self}{qw(day month year)} = ($1, $2, $3);
    }
    elsif (/\G(\d\d(?:\d\d)?)-(\d\d?)-(\d\d?)\b/gc) {
        # HYPHENDATE ([cc]yy-mm-dd)
        @{$self}{qw(year month day)} = ($1, $2, $3);
    }
    elsif (/\Gnow\b/gci) {
        # NOW
        $self->{now} = 1;
        $self->{date} = $now;
        return 1;
    }
    elsif (/\G(\d\d?)\s+($month_re)(?:\s+(\d\d(?:\d\d)?))?/gco) {
        # day_number month_name
        # day_number month_name year_number
        @{$self}{qw(day month_name year)} = ($1, $2, $3);
    }
    elsif (/\G(\d\d?)\/(\d\d?)\/(\d\d(?:\d\d)?)\b/gc) {
        # month_number '/' day_number '/' year_number
        @{$self}{qw(month day year)} = ($1, $2, $3);
    }
    elsif (/\G(\d\d?)(\d\d)(\d\d(?:\d\d)?)\b/gc) {
        # concatenated_date (m[m]dd[cc]yy)
        @{$self}{qw(month day year)} = ($1, $2, $3);
    }
    elsif (/\Gnext\s+($period_re)/gcio) {
        # NEXT inc_dec_period
        $self->{next_period} = $1;
        $self->{date} = $now->add(lc($1) => 1);
        return 1;
    }
    else {
        return;
    }

    $self->{month} //= $month{lc substr $self->{month_name}, 0, 3};

    if (defined (my $year = $self->{year})) {
        if (length $year <= 2) {
            $self->{year4} = $year + ($year < 70 ? 2000 : 1900);
        }
        else {
            $self->{year4} = $year;
        }
    }
    else {
        my $now_day = $now->day;
        my $now_month = $now->month;
        $self->{year4} = $now->year;
        $self->{year4}++ if ( ($now_month > $self->{month}) or
                              ( ($now_month == $self->{month}) and
                                ($now_day > $self->{day}) ) );
    }

    $self->{date} = DateTime->new(year => $self->{year4},
                                  month => $self->{month},
                                  day => $self->{day},
                                  hour => $now->hour,
                                  min => $now->minute,
                                  time_zone => $now->time_zone);

    return 1;


}

sub _parse_time {
    my $self = shift;

    if (/\G(\d\d)(\d\d)\b/gc) {
        # hr24clock_hr_min (hhmm)
        @{$self}{qw(hour min)} = ($1, $2);
    }
    elsif (/\G(([012]?[0-9])(?:[:'h,.](\d\d))?(?:\s*([ap]m))?\b)/gci) {
        # time_hour am_pm
        # time_hour_min
	# time_hour_min am_pm
        @{$self}{qw(hour min am_pm)} = ($2, ($3 // 0), $4);

        if (defined $4) {
            my $hour = $2;
            if ($hour > 11) {
                $hour > 12 and return;
                $hour = 0;
            }
            $hour += 12 if lc($4) eq 'pm';
            $self->{hour} = $hour;
        }
    }
    elsif (/\Gnoon\b/gc) {
        @{$self}{qw(hour min noon)} = (12, 0, 1);
    }
    elsif (/\Gmidnight\b/gc) {
        @{$self}{qw(hour min midnight)} = (0, 0, 1);
    }
    elsif (/\Gteatime\b/gc) {
        @{$self}{qw(hour min teatime)} = (16, 0, 1);
    }
    else {
        return
    }

    if (/\G\s*(utc)\b/gci) {
        $self->{tz} = uc $1;
        $self->{now}->set_time_zone($self->{tz});
    }

    return 1;
}

sub _parse_inc_or_dec {
    my $self = shift;
    return;
}

1;
__END__

=head1 NAME

DateTime::Format::GnuAt - Perl extension for blah blah blah

=head1 SYNOPSIS

  use DateTime::Format::GnuAt;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for DateTime::Format::GnuAt, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Salvador Fandiño, E<lt>salva@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Salvador Fandiño

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
