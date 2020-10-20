#!/usr/bin/perl

package skittles;

use warnings;
use strict;

use strict;
use IPC::Open2;
use Data::Dumper;
use FindBin;             # for finding the config file
use JSON::PP;            # for parsing the config file

# -------------------------------------------------------------------------------------------------
# Global Variables

my $gConfig;
my $gReactToSelf = 0;
my $gBotNickname = 0;
my @gSkittlesTicks;
my @gSkittlesFastTicks;

my ($heartInput, $heartOutput);

# -------------------------------------------------------------------------------------------------
# Main
{
    # Find and read config
    my $configText;
    my $configFilename = $FindBin::Bin . "/skittles.config";
    my $configFile;
    if(open($configFile, '<', $configFilename))
    {
        local $/ = undef;
        $configText = <$configFile>;
    }
    else
    {
        die "Cannot read config file: $configFilename";
    }

    # Parse config
    my $jsonParser = new JSON::PP;
    $gConfig = $jsonParser->loose(1)->decode($configText);
    if(!$gConfig)
    {
        die "Failed to parse config: $configFilename";
    }

    # Validate config
    unless(ref($gConfig) eq 'HASH')
    {
        die "config ($configFilename) must contain valid JSON that evaluates to an object";
    }
    for my $array (qw/rcfiles/)
    {
        unless(defined($gConfig->{$array}) and (ref($gConfig->{$array}) eq 'ARRAY'))
        {
            die "config ($configFilename) must supply an array of values named '$array'";
        }
    }

    # Prepare Skittles
    skittlesStartup();

    # trigger debugging (leave commented out)
    #my $triggers = [
    #    "<\\#740716217878446144>(.*)"
    #];
    #my $match = skittlesMatchTrigger($triggers, "<#740716217878446144> yeet");
    #print Dumper($match);
    #exit();

    # Initialize nickname
    $gBotNickname = $gConfig->{'nickname'};

    # Fire up the heart
    $|++;
    open2($heartOutput, $heartInput, "node heart/bin/heart");
    while(my $rawJSON = <$heartOutput>) {
        chomp($rawJSON);
        # print("Got: $rawJSON\n");

        my $ev = undef;
        eval {
            $ev = $jsonParser->loose(1)->decode($rawJSON);
        };
        if ($@) {
            print("Bad Event JSON: $rawJSON\n");
            next;
        }

        # print("Event: " . Dumper($ev));
        if(($ev->{'type'} eq 'msg')) {
            my $context = {
                channel => $ev->{'chan'},
                nick => $ev->{'user'},
                msg => $ev->{'text'},
                admin => 0
            };
            skittlesReact($context);
        } elsif($ev->{'type'} eq 'ftick') {
            processFastTicks();
        } elsif($ev->{'type'} eq 'tick') {
            processTicks();
        }
    }
}
exit();

# -------------------------------------------------------------------------------------------------
# Generic Helper Functions

sub fisher_yates_shuffle
{
    # Yaay Perl Cookbook
    my ($array) = @_;
    my $i;
    for ($i = @$array; --$i; )
    {
        my $j = int rand ($i+1);
        next if $i == $j;
        @$array[$i,$j] = @$array[$j,$i];
    }
}

# -------------------------------------------------------------------------------------------------
# Shuffled String Pool

sub poolCreate
{
    my($orig) = @_;
    return {
        orig => $orig,
        pool => [],
    };
}

sub poolPush
{
    my($pool, $str) = @_;
    push(@{ $pool->{'orig'} }, $str);
}

sub poolNext
{
    my($pool) = @_;
    if(scalar(@{ $pool->{'pool'} }) == 0)
    {
        @{ $pool->{'pool'} } = @{ $pool->{'orig'} };
        fisher_yates_shuffle($pool->{'pool'});
    }
    return shift(@{ $pool->{'pool'} });
}

# ---------------------------------------------------------------------------------------
# Core mods

sub mfCapture
{
    my($context) = @_;
    return $context->{'capture'};
}

sub mfNick
{
    my($context) = @_;
    return $context->{'nick'};
}

sub coreRegister
{
    skittlesRegisterMod('CAPTURE', \&mfCapture);
    skittlesRegisterMod('NICK', \&mfNick);
};

# -------------------------------------------------------------------------------------------------
# Speech

my $gSkittlesResources;
my %gSkittlesMods;
my @gSkittlesHooks;

sub skittlesRegisterMod
{
    my($key, $func, $data) = @_;

    my $mod = {
        key => $key,
        func => $func,
        data => $data,
    };
    $gSkittlesMods{$key} = $mod;

    print "Registered Mod: $key\n";
}

sub skittlesRegisterHook
{
    my($func) = @_;

    push(@gSkittlesHooks, $func);
}

sub skittlesRegisterTick
{
    my($func) = @_;

    push(@gSkittlesTicks, $func);
}

sub skittlesRegisterFastTick
{
    my($func) = @_;

    push(@gSkittlesFastTicks, $func);
}

# Shortcuts for mods to use
sub register    { return skittlesRegisterMod(@_);      } # alias
sub hook        { return skittlesRegisterHook(@_);     } # alias
sub tick        { return skittlesRegisterTick(@_);     } # alias
sub ftick       { return skittlesRegisterFastTick(@_); } # alias
sub broadcast   { return discordBroadcast(@_);         } # alias
sub say         { return discordSay(@_);               } # alias
sub config      { return $gConfig->{shift(@_)};        }

sub modPoolNext
{
    my ($mod) = @_;
    return poolNext($gSkittlesMods{$mod}->{'data'});
}

sub skittlesMatchNick
{
    my($list, $nick) = @_;
    return 1 if(scalar(@$list) == 0);

    for my $nicktrigger (@$list)
    {
        if($nick =~ /$nicktrigger/i)
        {
            return 1;
        }
    }
    return 0;
}

sub skittlesMatchTrigger
{
    my($list, $msg) = @_;
    my $ret = {
        trigger => "",
        capture => "",
    };
    return $ret if(scalar(@$list) == 0);

    for my $trigger (@$list)
    {
        my $interpTrigger = $trigger;
        $interpTrigger =~ s/!NICK!/$gBotNickname/g;
        if($msg =~ /$interpTrigger/i)
        {
            my $capture = $1;
            if(defined($capture))
            {
                $ret->{'capture'} = $capture;
                $ret->{'capture'} =~ s/^\s+//g;
                $ret->{'capture'} =~ s/\s+$//g;
            }
            $ret->{'trigger'} = $trigger;
            return $ret;
        }
    }
    return undef;
}

sub skittlesParse
{
    my ($resources, $filename) = @_;
    my $fh;
    my $currentSet = undef;

    open($fh, '<', $filename) or die "Can't open $filename.\n";
    while(my $line = <$fh>)
    {
        chomp($line);
        next if($line =~ m/^\s*#/); # Skip comments
        next if($line =~ m/^\s*$/); # Skip whitespace-only lines

        if($line =~ m/^set([qs])?\s+(\d+)\s+(\S+)/i)
        {
            my($q, $weight, $category) = ($1, $2, $3);
            my $quick = 0;
            my $split = 0;
            if($q eq 'q') {
                $quick = 1;
            }
            if($q eq 's') {
                $quick = 1;
                $split = 1;
            }

            if($weight > 0)
            {
                $currentSet = {
                    category => $category,
                    weight => $weight,
                    quick => $quick,
                    split => $split,
                    nicks => [],
                    channels => [],
                    triggers => [],
                    pool => poolCreate([]),
                };
                push(@{ $resources->{'sets'} }, $currentSet);
            }
            else
            {
                $currentSet = undef;
            }
        }

        # Nothing below this line in the loop makes sense without a current set
        # I should probably just return undef or die here.
        next unless($currentSet);

        if($line =~ m/^nick\s+(.+)$/i)
        {
            my $nick = $1;
            push(@{ $currentSet->{'nicks'} }, $nick);
        }
        elsif($line =~ m/^channel\s+(.+)$/i)
        {
            my $channel = $1;
            push(@{ $currentSet->{'channels'} }, $channel);
        }
        elsif($line =~ m/^trigger\s+(.+)$/i)
        {
            my $trigger = $1;
            push(@{ $currentSet->{'triggers'} }, $trigger);
        }
        elsif($line =~ m/^replyme\s+(.+)$/i)
        {
            my $reply = $1;
            $reply = "*$reply*";
            poolPush($currentSet->{'pool'}, $reply);
        }
        elsif($line =~ m/^kick\s+(.+)$/i)
        {
            my $reason = $1;
            $reason = "KICKPLZ $reason";
            poolPush($currentSet->{'pool'}, $reason);
        }
        elsif($line =~ m/^reply\s+(.+)$/i)
        {
            my $reply = $1;
            $reply =~ s/\\n/\n/g;
            poolPush($currentSet->{'pool'}, $reply);
        }
    }

    close($fh);
    return $resources;
}

sub skittlesStartup
{
    # Register core Skittles mods
    coreRegister();

    # Register all other Skittles mods (from mods subdir)
    my @modfiles = glob("mods/*.pm");
    for my $modfile (sort @modfiles)
    {
        print("Found mod: $modfile\n");
        require $modfile;
        my($modname) = ($modfile =~ m/([^\\\/]+).pm/i);
        if(!defined(eval("${modname}::register();")))
        {
            die("failed to run ${modname}::register()\n");
        }
    }

    $gSkittlesResources = {
        sets => []
    };

    for my $rcfile (@{ $gConfig->{'rcfiles'} })
    {
        if(!skittlesParse($gSkittlesResources, $rcfile))
        {
            die "Failed to parse '$rcfile'!";
        }
    }
}

sub splitWords
{
    my ($query) = @_;
    $query =~ s/^\s*//g;
    $query =~ s/\s*$//g;
    $query =~ s/[^a-zA-Z0-9_]//g;

    if(($query =~ /[A-Z]/) and ($query =~ /[a-z]/)) {
        # Mixed case; simply honor their requested split

        $query =~ s/([A-Z])/ $1/g;
        $query =~ s/^\s*//g;
        $query =~ s/\s*$//g;
        return $query;
    } else {
        # All one case; hand over to wordsplit
        $query = lc($query);

        my @words = map { chomp; $_ } `/home/joe/private/skittles/wordsplit \"$query\"`;
        my $result = join(" ", map { ucfirst($_) } @words);
        print("splitWords returned: $result\n");
        return $result;
    }
}

sub skittlesReact
{
    my ($context) = @_;

    for my $hook (@gSkittlesHooks)
    {
        &{ $hook }($context);
    }

    my $nick = $context->{'nick'};
    my $spoken_text = $context->{'msg'};

    # Walk all sets from the resource file, in order
    for my $s (@{ $gSkittlesResources->{'sets'} })
    {
        my $failedMod = undef;
        next unless(skittlesMatchNick($s->{'nicks'}, $context->{'nick'}));
        next unless(skittlesMatchNick($s->{'channels'}, $context->{'channel'}));

        my $match = skittlesMatchTrigger($s->{'triggers'}, $context->{'msg'});
        next unless(defined($match));
        $context->{'capture'} = $match->{'capture'};

        # See if we meet the X/1000 chances to reply
        my $chance = int(rand() * 1000);
        my $sayit = ($chance < $s->{'weight'});

        my $wEnabled = 0;
        if($context->{'msg'} =~ /\#w\b/)
        {
            $wEnabled = 1;
        }

        if($sayit)
        {
            my $quick = $s->{'quick'};
            my $split = $s->{'split'};
            my $replybase = poolNext($s->{'pool'}); # Grab the next reply in the pool for this set

            if($split) {
                $context->{'capture'} = splitWords($context->{'capture'});
            }

            my $reply = $replybase;
            for my $key (keys(%gSkittlesMods))
            {
                my $mod = $gSkittlesMods{$key};
                while($reply =~ /!\Q$key\E!/)
                {
                    my $replacement = &{ $mod->{'func'} }($context, $key, $mod->{'data'});
                    if(defined($replacement))
                    {
                        # $replacement =~ s/^\s+//g;
                        # $replacement =~ s/\s+$//g;
                        $reply =~ s/!\Q$key\E!/$replacement/;
                    }
                    else
                    {
                        $failedMod = $key;
                        last;
                    }
                }
                last if(defined($failedMod));
            }

            if(defined($failedMod))
            {
                print("Mod Failure: [$failedMod]: Skipping this response.\n");
                next;
            }

            if($wEnabled)
            {
                my @pieces = split(/http/, $reply);
                $pieces[0] =~ tr/rlRL/wwWW/;
                $reply = join("http", @pieces);
            }

            # $reply =~ s/`/\n/g;

            discordSay($context->{'channel'}, $reply, $quick);
            return 1;
        }
    }

    return 0;
}

sub processTicks
{
    my $context = {};
    for my $tick (@gSkittlesTicks)
    {
        &{ $tick }($context);
    }
}

sub processFastTicks
{
    my $context = {};
    for my $tick (@gSkittlesFastTicks)
    {
        &{ $tick }($context);
    }
}

# -------------------------------------------------------------------------------------------------
# Discord

sub discordLoad
{
    skittlesStartup();
}

sub discordEvent
{
    my($ev) = @_;
    print $heartInput encode_json($ev);
    print $heartInput "\n";
}

sub discordSay
{
    my($channel, $text, $quick) = @_;

    my $len = length($text);
    if($len < 1) {
        return;
    }

    my $delay =
        1              # time it took Skittles to 'read' the text he is replying to
      + (0.05 * $len); # time it took Skittles to "type" the reply

    if($delay > 2)
    {
        # clamping delay, as it was getting as long as 13 seconds at times
        $delay = 2;
    }

    if($quick) {
        $delay = 0;
    }

    $delay = int($delay * 1000);
    printf("Delaying by %d ms [%d chars]: %s\n", $delay, $len, $text);

    my $sev = {
        type => 'msg',
        chan => $channel,
        text => $text,
        delay => $delay,
    };
    discordEvent($sev);
}

sub discordBroadcast
{
    my($text, $quick) = @_;
    for my $channel (@{ $gConfig->{'broadcasts'} })
    {
        discordSay($channel, $text, $quick);
    }
}

