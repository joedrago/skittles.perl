package gw2wiki;

use warnings;
use strict;

use LWP::UserAgent;
use HTML::Entities;

# -------------------------------------------------------------------------------------------------
# Reaction: gw2wiki

sub mfWiki
{
    my($context, $key) = @_;
    my $capture = $context->{'capture'} // "";
    my $url = sprintf("http://wiki.guildwars2.com/index.php?go=Go&search=%s", encode_entities($capture));
    my $ua = new LWP::UserAgent;
    my $response = $ua->get($url);
    return $response->request->uri;
}

sub register
{
    skittles::register('GW2WIKI', \&mfWiki);
}

1;
