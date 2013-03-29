package news;

use warnings;
use strict;

use LWP::Simple;

# -------------------------------------------------------------------------------------------------
# Reaction: News

sub newsGetTop
{
    my $data = get("http://news.google.com/");
    my @elements = split(/</, $data);
    my @stories;
    my $found = 0;
    for my $e (@elements)
    {
        if($e =~ /class="topic-list"/)
        {
            $found = 1;
            next;
        }

        if($found)
        {
            last if($e =~ /^li/);

            if($e =~ /^a href="\/news\/section.+>([^>]+)/)
            {
                push(@stories, $1);
            }
        }
    }

    if(scalar(@stories) == 0)
    {
        return undef;
    }

    return join(", ", @stories);
}

sub mfNews
{
    my($context, $key) = @_;
    my $t = newsGetTop();
    return undef unless(defined($t));

    chomp($t);
    $t =~ s/\s+$//;
    $t =~ s/^\s+//;
    return $t;
}

sub register
{
    skittles::register('NEWS', \&mfNews);
}

1;
