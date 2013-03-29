package define;

use warnings;
use strict;

use JSON::PP;
use URI::Escape;
use HTML::Entities;
use LWP::Simple;

# -------------------------------------------------------------------------------------------------
# Define

sub localdefines
{
    my($text) = @_;
    my $fh;
    open($fh, '<', 'local_defines.txt') or return undef;
    my %defines;
    while(<$fh>)
    {
        chomp;
        if(/^([^:]+):\s*(.+)/)
        {
            push(@{$defines{lc($1)}}, $2);
        }
    }
    close($fh);

    return $defines{lc($text)};
}

my $lastDefine = "";
my $lastIndex = 0;
my $lastEntries = undef;

sub fixdefine
{
    my($t) = @_;
    $t =~ s/\\x26/&/g;
    $t = uri_unescape($t);
    return $t;
}

sub define
{
    my ($text) = @_;

    my $entries = undef;
    my $which = 0;
    if(defined($lastDefine) and ($lastDefine eq $text))
    {
        print "Using cached define '$text'\n";
        $entries = $lastEntries;
        $lastIndex = ($lastIndex+1) % scalar(@$entries);
        $which = $lastIndex;
    }
    else
    {
        print "Looking up '$text'\n";
        my $url = "http://www.google.com/dictionary/json?callback=hurr&q="
            . uri_escape($text)
            . "&sl=en&tl=en&restrict=pr,de&client=te";

        my $out = get($url);
        if($out)
        {
            $out =~ s/^hurr[(]//s;
            $out =~ s/,\d+,null[)]$//is;
            $out =~ s/\\x(..)/\\u00$1/g;
            my $json = new JSON::PP;
            my $data = $json->loose(1)->decode($out);
            if($data)
            {
                my $rawentries = $data->{'webDefinitions'}[0]->{'entries'};
                if($rawentries)
                {
                    my @t = map { decode_entities($_->{'terms'}[0]->{'text'}) } @$rawentries;
                    $entries = \@t;
                    $lastEntries = $entries;
                    $lastIndex = 0;
                    $which = $lastIndex;
                }
            }
        }

        my $local_defines = localdefines($text);
        if(defined($local_defines))
        {
            $entries = [] unless(defined($entries));

            $lastEntries = $entries;
            $lastIndex = 0;
            $which = $lastIndex;
            unshift(@$entries, @$local_defines);
        }
    }

    unless(defined($entries))
    {
        return undef;
    }

    $lastDefine = $text;

    my $def = $entries->[$which];
    if($def)
    {
        $def = sprintf("[%d/%d] $def", $which+1, scalar(@$entries));
        return $def;
    }
    return undef;
}

sub mfDefine
{
    my($context) = @_;
    my $query = $context->{'capture'};
    my $def = define($query);
    if(!defined($def))
    {
        my $failureReply = skittles::config("define_unknown");
        if(!$failureReply)
        {
            $failureReply = "[definition unknown]";
        }
        return $failureReply;
        return 1;
    }
    return $def;
}

sub register
{
    skittles::register('DEFINE', \&mfDefine);
}

1;
