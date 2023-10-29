package WWW::YTWalker;
use 5.010;
use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use Exporter 'import';
use YAML::Syck qw(LoadFile DumpFile Dump);
use Const::Fast;
use Try::Tiny;
use File::Share ':all';
use Filesys::DfPortable;
use List::Util           qw(first);
use Number::Bytes::Human qw(format_bytes parse_bytes);
use IPC::Cmd             qw(can_run run QUOTE);
use Log::Dispatch;
use Time::Piece;
use FindBin::libs "Bin=${FindBin::RealBin}";
use open ':std' => ':utf8';

use version 0.77; our $VERSION = version->declare("v0.0.1");

our @EXPORT = qw(
    YTWalker showChannels
    loadConfig createLogger getAvailableDisk sysQuote save saveOne filterLog
);
const my @LogLevels => qw(debug info notice warning error critical alert emergency);
const my @regSkipBase => qw{
    Downloading\spage\s\d+
    Downloading\svideo\s\d+\sof\s\d+
    has\salready\sbeen\srecorded\sin\sarchive
    Total\sfragments:\s+\d+
    [0-9\.]+%\s+of\s+~[0-9.]+(Ki|Mi|Gi)B\s+at\s+[0-9.]+(Ki|Mi|Gi)B/s\sETA\s[0-9:]+
    Requested\sformats\sare\sincompatible
};
const my @regNotMatch => qw{
    title\sdid\snot\smatch\spattern
};
const my @regSchedule => qw{
    Premieres\sin\s\d+\s(minutes|hours|days)
    This\slive\sevent\swill\sbegin\sin\s\d+\s(minutes|hours|days)
};

$YAML::Syck::ImplicitUnicode = 1;

my $conf = loadConfig();
my $logger;
my $youtube_dl = can_run('youtube-dl') or die("youtube-dl is not found");
my $regSkip;

sub YTWalker {
    my $opts     = shift;
    my $channels = shift;
    $logger = createLogger($opts);
    $logger->info( "Options:\n" . Dump($opts) );
    my @regSkip = (
        @regSkipBase,
        ( !${ $opts->{'notMatch'} } ? @regNotMatch : () ),
        ( !${ $opts->{'schedule'} } ? @regSchedule : () ),
    );
    $regSkip = join( "|", @regSkip );
    $logger->debug( "regSkip:\n" . join( "\n", @regSkip ) . "\n" );
    my @channels
        = @{$channels}
        ? grep { exists( $conf->{'Channels'}{$_} ) } @{$channels}
        : sort( keys( %{ $conf->{'Channels'} } ) );
    my $index = 0;

    foreach my $channel (@channels) {
        my $name     = $conf->{'Channels'}{$channel}{'Name'} || '';
        my $progress = sprintf( "(%d/%d)", ++$index, scalar(@channels) );
        my $title    = join( " ", grep {$_} ( '#', $channel, $name, $progress ) );
        $logger->notice($title);
        save($channel);
        $logger->notice("");
    }
}

sub showChannels {
    my @channels = sort( keys( %{ $conf->{'Channels'} } ) );
    foreach my $channel (@channels) {
        my $info = $conf->{'Channels'}{$channel};
        my $name = $info->{'Name'} || '';
        say("${channel} ${name}");
        if ( $info->{'Regex'} ) {
            say("  $info->{Regex}");
        }
    }
}

sub loadConfig {
    my $fname = shift || 'config';
    my $dir   = try { dist_dir('WWW-YTWalker') } catch {""};
    my $file  = "${dir}/conf/${fname}.yml";
    if ( !( -f $file ) && $fname eq 'config' ) {
        $file = "${dir}/conf/config_default.yml";
    }
    if ( !( -f $file ) ) {
        warn("Mot Found: ${fname}");
        return undef;
    }
    my $conf = LoadFile($file);
    if ( !$conf ) {
        warn("${file}: $!");
        return undef;
    }
    return $conf;
}

sub createLogger {
    my $opts = shift;
    my $level
        = ( grep { $_ eq ${ $opts->{'log'} } } @LogLevels )
        ? ${ $opts->{'log'} }
        : 'notice';
    my $fname   = $conf->{'LogDir'} . '/' . (localtime)->strftime('%Y%m%d-%H%M%S') . '.log';
    my $outputs = [ [ 'Screen', min_level => 'error', newline => 1, ], ];
    push(
        @{$outputs},
        [   'File',
            min_level   => $level,
            filename    => encode( 'UTF-8', $fname ),
            binmode     => ":utf8",
            permissions => 0666,
            newline     => 1,
        ]
    );
    return Log::Dispatch->new( outputs => $outputs, );
}

sub getAvailableDisk {
    my $space = $conf->{'LeastFreeSpace'};
    my $byte  = parse_bytes($space) or die("Invalid LeastFreeSpace: ${space}");
    my $dir   = first { $_->{'bavail'} > $byte }
        map {
        my $info = dfportable($_) or die("$_: $!");
        {   dir    => $_,
            bavail => $info->{'bavail'},
        };
        } grep { $_ && -d "$_/" } @{ $conf->{'SaveDirs'} };
    return !$dir
        ? undef
        : $dir->{'dir'};
}

sub sysQuote {
    return QUOTE . $_[0] . QUOTE;
}

sub save {
    my $channel = shift;
    my $info    = $conf->{'Channels'}{$channel};
    if ( $info->{'Type'} eq 'Channel' ) {
        foreach my $path (qw(videos shorts streams)) {
            saveOne( Channel => $channel, Uri => "$info->{Uri}/$path", Regex => $info->{'Regex'} );
        }
    } elsif ( $info->{'Type'} eq 'PlayList' ) {
        saveOne( Channel => $channel, Uri => $info->{'Uri'}, Regex => $info->{'Regex'} );
    }
}

sub saveOne {
    my $info = {@_};
    my $dest = getAvailableDisk();
    if ( !$dest ) {
        $logger->error("Diskfull");
        return 0;
    }
    chdir($dest) or die("$dest: $!");
    my $cmd
        = !$info->{'Regex'}
        ? sprintf( '%s %s', $youtube_dl, sysQuote( $info->{'Uri'} ) )
        : sprintf(
        '%s --match-title %s %s',
        $youtube_dl,
        sysQuote( $info->{'Regex'} ),
        sysQuote( $info->{'Uri'} )
        );
    my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf )
        = run( command => $cmd, verbose => 0, timeout => 120 * 60 );
    if ( $full_buf && @{$full_buf} ) {
        filterLog( $full_buf, $info->{'Channel'} );
    }
    return $success;
}

sub filterLog {
    my $buf     = shift;
    my $channel = shift;
    my @log     = grep { $_ !~ /$regSkip/x } split( "\n", decode( 'UTF-8', join( "", @{$buf} ) ) );
    foreach my $line (@log) {
        if ( $line =~ /^ERROR:\s/ ) {
            $logger->error("${line} in ${channel}");
        } else {
            $logger->info($line);
        }
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

WWW::YTWalker - It's new $module

=head1 SYNOPSIS

    use WWW::YTWalker;

=head1 DESCRIPTION

WWW::YTWalker is ...

=head1 LICENSE

Copyright (C) TakeAsh.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

L<TakeAsh68k|https://github.com/TakeAsh/>

=cut

