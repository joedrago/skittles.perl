package bro;

use warnings;
use strict;

use TeX::Hyphen;

# ---------------------------------------------------------------------------------------
# Bro code

sub mfBro
{
    my($context, $key, $data) = @_;
    my $text = $context->{'capture'} // "";
    $text =~ s/[^a-z0-9 .,\/:_?!@+]//ig;
    my @words = sort { length($b) <=> length($a) } grep { !/,/ } split(/\s+/, $text);

    if(scalar(@words))
    {
        my $word = $words[0];

        my $hyp = new TeX::Hyphen;
        my @p = split(/-/, $hyp->visualize($word));
        $p[int(rand(scalar(@p)))] = 'bro';

        return join('', @p);
    }
    return "";
}

sub register
{
    skittles::register('BRO', \&mfBro);
}

1;
