package inspirations;

use strict;
use Image::Magick;
use MIME::Base64;
use POSIX;
use Data::Dumper;

my @randombg;
my %available;

sub mfInspirationsCreate
{
    my($context, $capture) = @_;
    my $query = $context->{'capture'};

    my $quote = $query;
    chomp($quote);
    $quote =~ s/^\s+//g;
    $quote =~ s/\s+$//g;

    my $output = generateInspirations(
        quote => $quote,
        author => $context->{'nick'},
        dir => skittles::config("meme_dir"),
    );

    if($output)
    {
        return "http://skittles.gotdoofed.com/memes/$output";
    }
    return "Failed to create meme.";
}

sub mfInspirationsQuote
{
    my($context, $capture) = @_;
    my $query = $context->{'capture'};

    if($query =~ /\s*(\"[^\"]+\"|\S+)\s+(.+)/)
    {
        my($who, $what) = ($1, $2);
        my $quote = $what;
        chomp($quote);
        $quote =~ s/^\s+//g;
        $quote =~ s/\s+$//g;
        $who =~ s/^\s+//g;
        $who =~ s/\s+$//g;
        $who =~ s/^\"//g;
        $who =~ s/\"$//g;

        my $output = generateInspirations(
            quote => $quote,
            author => $who,
            dir => skittles::config("meme_dir"),
        );

        if($output)
        {
            return "http://skittles.gotdoofed.com/memes/$output";
        }
        return "Failed to create meme.";
    }
    return "wat?";
}

sub register
{
    @randombg = ();
    %available = ();
    my @bgs = glob("inspirations/*.jpg");
    for my $bg (@bgs)
    {
        if($bg =~ /\/([^\/]+)\.jpg/)
        {
            my $base = $1;
            print("Background: $base\n");
            push(@randombg, $base);
            $available{$base}++;
        }
    }
    skittles::register("INSPIRATIONS", \&mfInspirationsCreate);
    skittles::register("QUOTE", \&mfInspirationsQuote);
}

register();

sub generateInspirations
{
    my %o = @_;
    my $top = undef;
    my $quote = undef;
    my $bg = undef;
    my $output = undef;
    my $dir = "";

    printf("generateInspirations:%s\n", Dumper(\%o));

    my $author = $o{'author'};

    if($o{'top'})
    {
        $top = $o{'top'};
    }
    if($o{'quote'})
    {
        $quote = $o{'quote'};
    }
    if($o{'bg'})
    {
        $bg = $o{'bg'};
    }
    else
    {
        $bg = $randombg[ int(rand(scalar(@randombg))) ];
        print("picking random bg: '$bg'\n");
    }
    if($o{'dir'})
    {
        $dir = $o{'dir'};
    }
    $bg =~ s/[^a-zA-Z0-9_]//g;
    $bg = lc($bg);

    my $meme = new Image::Magick;

    my $fh;
    my $fn = "inspirations/$bg.jpg";
    if(!open($fh, '<', $fn))
    {
        print("ERROR: cant open '$fn'\n");
        return undef;
    }
    binmode($fh);
    $meme->Read(file => $fh);
    close($fh);

    my $rows = int($meme->Get('rows'));
    my $cols = int($meme->Get('columns'));
    my $pointsize = 36;
    my $stroke_width = $pointsize / 30.0;
    my $x_position = $cols / 2;
    my $y_position = $rows * 0.15;

    my $ox = 30;
    my $oy = 20;

    if($quote)
    {
        my($scale, $wrapped) = scale_text($quote);

        $wrapped = ucfirst($wrapped);
        unless($wrapped =~ /[\.\?\!]$/)
        {
            $wrapped = "$wrapped.";
        }
        $wrapped = "$wrapped\n- $author";

        printf("Bottom: Scale %2.2f, text:\n%s\n", $scale, $wrapped);

        my $font = skittles::config("inspirations_font");

        $meme->Annotate(
            font => $font,
            text => $wrapped,
            #"interline-spacing" => -($pointsize / 8),
            antialias => 1,
            #stroke => "black",
            fill => "black",
            gravity => "SouthEast",
            x => $ox+0,
            y => $oy+0,
            #strokewidth => $stroke_width * $scale,
            pointsize => $pointsize * $scale,
        );

        $meme->Annotate(
            font => $font,
            text => $wrapped,
            #"interline-spacing" => -($pointsize / 8),
            antialias => 1,
            #stroke => "white",
            fill => "white",
            gravity => "SouthEast",
            x => $ox+3,
            y => $oy+3,
            size => "${cols}x",
            #strokewidth => $stroke_width * $scale,
            #strokewidth => 0,
            pointsize => $pointsize * $scale,
        );
    }

    my $output = strftime("%Y%m%d%H%M%S", localtime);
    $output .= sprintf("_%d.jpg", int(rand() * 100));

#debug
#$output = "1.jpg";

    printf("writing to $dir$output");
    open($fh, '>', "$dir$output");
    $meme->Write(file => $fh);
    close($fh);

    return $output;
}

sub word_wrap
{
    my($txt, $col) = @_;
    if(!$col)
    {
        $col = 80;
    }

    $txt =~ s/(.{$col}[^\s]*)\s+/$1\n/g;
    return $txt;
}

sub scale_text
{
    my($text) = @_;
    my $len = length($text);
    my $scale = 1.0;

    $text = word_wrap($text, 60);

#    if($len < 6)
#    {
#        $scale = 1.0;
#    }
#    elsif($len < 50)
#    {
#        $text = word_wrap($text, 18);
#        $scale = 0.5;
#    }
#    else
#    {
#        $text = word_wrap($text, 35);
#        $scale = 0.4;
#    }

    chomp($text);

    return ($scale, $text);
}

1;
