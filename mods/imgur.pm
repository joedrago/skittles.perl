package imgur;

use warnings;
use strict;

use LWP::Simple;
use HTML::Entities;

# -------------------------------------------------------------------------------------------------
# Reaction: Imgur

sub mfImgur
{
    my($context) = @_;
    my $url = $context->{'capture'};
    $url =~ s/^https/http/;
    my $title = undef;
    my $content = get($url);
    if(defined($content))
    {
        if($content =~ /<title>(.*)<\/title>/igs)
        {
            $title = $1;
            $title = decode_entities($title);
            $title =~ tr/\x20-\x7f//cd;
            if($title =~ /(.+)-\s+[^-]+$/)
            {
                $title = $1;
            }
            $title =~ s/^\s+//;
            $title =~ s/\s+$//;
        }
    }
    return $title;
}

sub register
{
    skittles::register('IMGUR', \&mfImgur);
}

1;
