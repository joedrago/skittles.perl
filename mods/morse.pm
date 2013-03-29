package morse;

use strict;

# -------------------------------------------------------------------------------------------------
# Reaction: Morse

sub mfMorse
{
    my($context, $key) = @_;
    my $morseCode = skittles::config("morse_codes");
    if(!$morseCode)
    {
        $morseCode = "x X";
    }
    my ($dot, $dash) = split(/ /, $morseCode);
    my %ENGLISH = qw(
    A .-
    B -...
    C -.-.
    D -..
    E .
    F ..-.
    G --.
    H ....
    I ..
    J .---
    K -.-
    L .-..
    M --
    N -.
    O ---
    P .--.
    Q --.-
    R .-.
    S ...
    T -
    U ..-
    V ...-
    W .--
    X -..-
    Y -.--
    Z --..
    . .-.-.-
    / -...-
    : ---...
    ' .----.
    - -....-
    ? ..--..
    ! ..--.
    @ ...-.-
    + .-.-.
    0 -----
    1 .----
    2 ..---
    3 ...--
    4 ....-
    5 .....
    6 -....
    7 --...
    8 ---..
    9 ----.
    );

    $ENGLISH{','} = '--..--';

    my $text = $context->{'capture'} // "";
    $text =~ s/[^a-z0-9 .,\/:'_?!@+]//ig;
    my @words = split(/\s+/, $text);
    my @code;
    for my $word (@words) {
        my @letters = split(//, $word);
        my $morse = "";
        for my $letter (@letters)
        {
            if($morse)
            {
                $morse .= "_";
            }
            $morse .= $ENGLISH{uc($letter)};
        }
        $morse =~ s/\./$dot/g;
        $morse =~ s/\-/$dash/g;
        $morse =~ s/_/-/g;
        push(@code, $morse);
    }

    return join(" ", @code);
}

sub register
{
    skittles::register('MORSE', \&mfMorse);
}

1;
