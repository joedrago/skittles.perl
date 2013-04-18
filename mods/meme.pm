package meme;

use strict;
use Image::Magick;
use MIME::Base64;
use POSIX;
use Data::Dumper;

my @randombg;
my %available;

sub mfMemeList
{
    my $list = word_wrap(join(", ", sort(@randombg)), 400);
    return "memes: $list";
}

sub mfMemeCreate
{
    my($context, $capture) = @_;
    my $query = $context->{'capture'};
    my @pieces = map { chomp; s/^\s+//g; s/\s+$//g; $_} split(/\//, $query);

    printf("Raw input:\n%s\n", Dumper(\@pieces));

    my $top = "";
    my $bottom = "";
    my $bg = "";

    my $count = scalar(@pieces);
    if($count == 1)
    {
        $bottom = $pieces[0];
    }
    elsif($count == 2)
    {
        $top = $pieces[0];
        $bottom = $pieces[1];
    }
    elsif($count == 3)
    {
        $bg = lc($pieces[0]);
        if(!$available{$bg})
        {
            $bg = "";
        }
        $top = $pieces[1];
        $bottom = $pieces[2];
    }

    my $output = generateMeme(
        top => $top,
        bottom => $bottom,
        bg => $bg,
        dir => skittles::config("meme_dir"),
    );

    if($output)
    {
        return "http://skittles.gotdoofed.com/memes/$output";
    }
    return "Failed to create meme.";
}

sub register
{
    @randombg = ();
    %available = ();
    my @bgs = glob("backgrounds/*.jpg");
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
    skittles::register("MEMECREATE", \&mfMemeCreate);
    skittles::register("MEMELIST", \&mfMemeList);
}

register();

sub generateMeme
{
    my %o = @_;
    my $top = undef;
    my $bottom = undef;
    my $bg = undef;
    my $output = undef;
    my $dir = "";

    printf("generateMeme:%s\n", Dumper(\%o));

    if($o{'top'})
    {
        $top = uc($o{'top'});
    }
    if($o{'bottom'})
    {
        $bottom = uc($o{'bottom'});
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
    my $fn = "backgrounds/$bg.jpg";
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
    my $pointsize = $cols / 5.0;
    my $stroke_width = $pointsize / 25.0;
    my $x_position = $cols / 2;
    my $y_position = $rows * 0.15;

    if($top)
    {
        my($scale, $wrapped) = scale_text($top);

        printf("Top: Scale %2.2f, text:\n%s\n", $scale, $wrapped);

        my $ret = $meme->Annotate(
            font => "Impact.ttf",
            text => $wrapped,
            "interline-spacing" => -($pointsize / 8),
            antialias => 1,
            stroke => "black",
            fill => "white",
            gravity => "North",
            strokewidth => $stroke_width * $scale,
            pointsize => $pointsize * $scale,
        );
    }

    if($bottom)
    {
        my($scale, $wrapped) = scale_text($bottom);

        printf("Bottom: Scale %2.2f, text:\n%s\n", $scale, $wrapped);

        my $ret = $meme->Annotate(
            font => "Impact.ttf",
            text => $wrapped,
            "interline-spacing" => -($pointsize / 8),
            antialias => 1,
            stroke => "black",
            fill => "white",
            gravity => "South",
            strokewidth => $stroke_width * $scale,
            pointsize => $pointsize * $scale,
        );
    }

    my $output = strftime("%Y%m%d%H%M%S", localtime);
    $output .= sprintf("_%d.png", int(rand() * 100));

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

    if($len < 6)
    {
        $scale = 1.0;
    }
    elsif($len < 20)
    {
        $text = word_wrap($text, 9);
        $scale = 0.6;
    }
    else
    {
        $text = word_wrap($text, 13);
        $scale = 0.4;
    }

    chomp($text);

    return ($scale, $text);
}

1;
