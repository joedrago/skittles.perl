package youtubesearch;

use warnings;
use strict;

use HTML::Entities;
use LWP::Simple;
use XML::Simple;

# -------------------------------------------------------------------------------------------------
# Reaction: Youtube Search

sub xpath
{
    my($data, $path) = @_;
    my @pieces = split(/ /, $path);
    for my $piece (@pieces)
    {
        $data = $data->{$piece};
        if(!defined($data))
        {
            return undef;
        }
        if(ref($data) eq 'ARRAY')
        {
            $data = $data->[0];
        }
    }
    return $data;
}

sub mfYoutubeSearch
{
    my($context) = @_;
    my $url = sprintf("http://gdata.youtube.com/feeds/api/videos?alt=rss&racy=include&vq=%s&start-index=1&max-results=1", encode_entities($context->{'capture'}));
    my $title = undef;
    my $content = get($url);
    if(defined($content))
    {
        my $data = XMLin($content, ForceArray => 1);
        my $url = xpath($data, "channel item link");
        my $title = xpath($data, "channel item media:group media:title content");
        $url =~ s/&?feature=[^&]+//g;
        return sprintf("First hit: \"%s\" %s", $title, $url);
    }
    return "No videos found.";
}

sub register
{
    skittles::register('YOUTUBESEARCH', \&mfYoutubeSearch);
}

1;
