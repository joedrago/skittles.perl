package madlib;

use warnings;
use strict;

use FindBin;

# ---------------------------------------------------------------------------------------
# Madlibs code

sub mfMadlib
{
    my($context, $key, $pool) = @_;
    return skittles::poolNext($pool);
}

sub register
{
    my $madlibsDir = $FindBin::Bin . "/madlibs";
    print("MadLibs Data: $madlibsDir\n");

    my @files = glob("$madlibsDir/*.txt");
    for my $file (@files)
    {
        my ($name) = $file =~ /([^\\\/]+)\.txt/;
        $name = uc($name);

        my $f;
        if(open($f, '<', $file))
        {
            my $pool = skittles::poolCreate([grep { !/^\s*$/ } map { chomp; $_ } <$f>]);
            skittles::register("ML_$name", \&mfMadlib, $pool);
            close($f);
        }
    }
}

1;
