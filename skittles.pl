#!/usr/bin/perl

package skittles;

use warnings;
use strict;

use strict;
use IPC::Open2;
use Data::Dumper;
use POSIX qw/strftime/;  # for fancy timestamps in logs
use FindBin;             # for finding the config file
use JSON::PP;            # for parsing the config file

# -------------------------------------------------------------------------------------------------
# Global Variables

my $gConfig;
my $gReactToSelf = 0;
my $gBotNickname = 0;
my @gSkittlesTicks;

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

    # Init logging
    logInit();

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

        print("Event: " . Dumper($ev));
        if(($ev->{'type'} eq 'msg')) {
            my $context = {
                channel => $ev->{'chan'},
                nick => $ev->{'user'},
                msg => $ev->{'text'},
                admin => 0
            };
            logMessage($ev->{'user'}, $ev->{'text'});
            skittlesReact($context);
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

# Shortcuts for mods to use
sub register    { return skittlesRegisterMod(@_);  } # alias
sub hook        { return skittlesRegisterHook(@_); } # alias
sub tick        { return skittlesRegisterTick(@_); } # alias
sub broadcast   { return discordBroadcast(@_);     } # alias
sub config      { return $gConfig->{shift(@_)};    }

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
    $query =~ s/[^a-zA-Z_]//g;
    $query = lc($query);

    my @words = map { chomp; $_ } `/home/joe/private/skittles/wordsplit \"$query\"`;
    my $result = join(" ", map { ucfirst($_) } @words);
    print("splitWords returned: $result\n");
    return $result;
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

        my $logEntry = {
            type => 'match',
            srcnick => $nick,
            srctext => $spoken_text,
            category => $s->{'category'},
            trigger => $match->{'trigger'},
            chance => $chance,
            threshold => $s->{'weight'},
            fired => ($sayit) ? 'hit' : 'miss',
        };

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

            $logEntry->{'replybase'} = $replybase;
            $logEntry->{'reply'} = $reply;

            # $reply =~ s/`/\n/g;

            discordSay($context->{'channel'}, $reply, $quick);
            logMessage($gBotNickname, $reply, $quick);
            $logEntry->{'replytype'} = 'say';
            logAppend($logEntry);
            return 1;
        }
        else
        {
            # Log the failed chance
            logAppend($logEntry);
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

# -------------------------------------------------------------------------------------------------
# Discord

sub discordLoad
{
    skittlesStartup();
}

sub discordSay
{
    my($channel, $text, $quick) = @_;

    my $len = length($text);
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
    print $heartInput encode_json($sev);
    print $heartInput "\n";
}

sub discordBroadcast
{
    my($text, $quick) = @_;
    for my $channel (@{ $gConfig->{'broadcasts'} })
    {
        discordSay($channel, $text, $quick);
    }
}

# -------------------------------------------------------------------------------------------------
# Logging

sub LOG_COLUMNS() { qw/timestamp datetime date dayofweek type srcnick srctext category trigger replytype replybase reply chance threshold fired/ }

sub logCreate
{
    return if(-f $gConfig->{'log'});

    my $fh;
    open($fh, '>', $gConfig->{'log'}) or die "cannot open ".$gConfig->{'log'}." for write";
    my @quotedColumns = map { "\"$_\"" } LOG_COLUMNS;
    my $line = join(",", @quotedColumns) . "\n";
    print $fh $line;
    close($fh);
}

sub logInit
{
    logCreate();
}

sub logMessage
{
    my($nick, $text) = @_;

    logAppend({
            type => 'message',
            srcnick => $nick,
            srctext => $text,
            });
}

sub logAppend
{
    my($entry) = @_;
    my $now = time();

    $entry->{'timestamp'} = $now;
    $entry->{'datetime'} = strftime("%F %T", localtime($now));
    $entry->{'date'} = strftime("%F", localtime($now));
    $entry->{'dayofweek'} = strftime("%w", localtime($now));

    logCreate();

    my @outputColumns;
    for my $col (LOG_COLUMNS)
    {
        my $text = "";
        if(defined($entry->{$col}))
        {
            $text = $entry->{$col};
        }
        $text =~ s/\r/ /g;
        $text =~ s/\n/ /g;
        $text =~ s/"/""/g;
        $text = "\"$text\"";
        push(@outputColumns, $text);
    }

    my $fh;
    open($fh, '>>', $gConfig->{'log'}) or die "cannot open ".$gConfig->{'log'}." for write";
    my $line = join(",", @outputColumns) . "\n";
    print $fh $line;
    close($fh);
}

