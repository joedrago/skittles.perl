#!/usr/bin/perl

package skittles;

use warnings;
use strict;

use POE;                 # base Perl Object Environment event system
use POE::Component::IRC; # POE IRC client code
use POSIX qw/strftime/;  # for fancy timestamps in logs
use FindBin;             # for finding the config file
use JSON::PP;            # for parsing the config file

# -------------------------------------------------------------------------------------------------
# Global Variables

my $gConfig;
my $gBotNickname;

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
    for my $array (qw/channels rcfiles/)
    {
        unless(defined($gConfig->{$array}) and (ref($gConfig->{$array}) eq 'ARRAY'))
        {
            die "config ($configFilename) must supply an array of values named '$array'";
        }
    }
    for my $string (qw/nickname host port/) # 'log' not required
    {
        unless(defined($gConfig->{$string}) and not ref($gConfig->{$string}))
        {
            die "config ($configFilename) must supply a single '$string' value";
        }
    }

    # Initialize nickname
    $gBotNickname = $gConfig->{'nickname'};

    # Register core Skittles mods
    coreRegister();

    # Register all other Skittles mods (from mods subdir)
    my @modfiles = glob("mods/*.pm");
    for my $modfile (sort @modfiles)
    {
        require $modfile;
        my($modname) = ($modfile =~ m/([^\\\/]+).pm/i);
        if(!defined(eval("${modname}::register();")))
        {
            die("failed to run ${modname}::register()\n");
        }
    }

    # Init logging
    logInit();

    # Load RC file and create POE session
    ircLoad();
    ircStartup();

    # This does all the work.
    POE::Kernel->run();
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

# -------------------------------------------------------------------------------------------------
# POE Session Hooks

sub poeSessionStart
{
    my $kernel  = $_[KERNEL];
    my $heap    = $_[HEAP];
    my $session = $_[SESSION];

    $kernel->post( IRC => register => "all" );

    my $connectOptions = {
        Nick     => $gBotNickname,
        Username => $gBotNickname,
        Ircname  => $gBotNickname,
        Server   => $gConfig->{'host'},
        Port     => $gConfig->{'port'},
    };

    $kernel->post( IRC => connect => $connectOptions);
}

sub poeSessionConnect
{
    my $kernel = $_[KERNEL];
    for my $channel (@{ $gConfig->{'channels'} })
    {
        $kernel->post( IRC => join => $channel );
        if($gConfig->{'hello'} and not ref($gConfig->{'hello'}))
        {
            $kernel->post( IRC => privmsg => $channel, $gConfig->{'hello'});
        }
    }
}

sub poeSessionJoin
{
    my ($kernel, $who, $where) = @_[KERNEL, ARG0, ARG1];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where;

    if($gConfig->{'all_op'})
    {
        # Makes everyone an operator, if Skittles is
        $kernel->post( IRC => mode => $channel, "+o", $nick);
    }
    print "$nick joined $channel\n";
}

sub poeSessionPrivate
{
    my ($kernel, $who, $where, $msg) = @_[KERNEL, ARG0, ARG1, ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where;

    print "Private Message From $nick: $msg\n";
    my $context = {
        kernel => $kernel,
        channel => $channel,
    };

    if($gConfig->{'reload'})
    {
        if($msg =~ /reload/)
        {
            ircLoad();
            ircTell($context, $nick, "Reloaded sets.");
        }
    }
}

sub poeSessionNick
{
    my ($kernel, $who, $newnick) = @_[KERNEL, ARG0, ARG1];
    my $onick = ( split /!/, $who )[0];
    my $nnick = ( split /!/, $newnick )[0];

    if($onick eq $gBotNickname)
    {
        $gBotNickname = $nnick;
        print "New Bot Nick Detected: $nnick\n";
    }

    print "($onick eq $gBotNickname) $nnick\n";
}

sub poeSessionPublic
{
    my ( $kernel, $who, $where, $msg ) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    my $ts = scalar localtime;
    print " [$ts] <$nick:$channel> $msg\n";

    my $context = {
        kernel => $kernel,
        channel => $channel,
        nick => $nick,
        msg => $msg,
        admin => 0
    };
    logMessage($nick, $msg);
    skittlesReact($context);
}

sub poeRespond
{
    my $kernel   = $_[KERNEL];
    my $response = $_[ARG0];
    my $type     = $response->{'type'};

    if($type eq 'say')
    {
        $kernel->post(IRC => privmsg => $response->{'channel'}, $response->{'text'});
    }
    elsif($type eq 'tell')
    {
        $kernel->post(IRC => privmsg => $response->{'nick'}, $response->{'text'});
    }
    elsif($type eq 'kick')
    {
        $kernel->post(IRC => kick => $response->{'channel'}, $response->{'nick'}, $response->{'text'});
    }
    elsif($type eq 'emote')
    {
        $kernel->post(IRC => privmsg => $response->{'channel'}, chr(1) . "ACTION " . $response->{'text'} . chr(1) );
    }
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

# Shortcuts for mods to use
sub register { return skittlesRegisterMod(@_); } # alias
sub config   { return $gConfig->{shift(@_)};   }

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

        if($line =~ m/^set\s+(\d+)\s+(\S+)/i)
        {
            my($weight, $category) = ($1, $2);

            if($weight > 0)
            {
                $currentSet = {
                    category => $category,
                    weight => $weight,
                    nicks => [],
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
        elsif($line =~ m/^trigger\s+(.+)$/i)
        {
            my $trigger = $1;
            push(@{ $currentSet->{'triggers'} }, $trigger);
        }
        elsif($line =~ m/^replyme\s+(.+)$/i)
        {
            my $reply = $1;
            $reply = "ACTION $reply";
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
            poolPush($currentSet->{'pool'}, $reply);
        }
    }

    close($fh);
    return $resources;
}

sub skittlesStartup
{
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

sub skittlesReact
{
    my ($context) = @_;

    my $nick = $context->{'nick'};
    my $spoken_text = $context->{'msg'};

    # Walk all sets from the resource file, in order
    for my $s (@{ $gSkittlesResources->{'sets'} })
    {
        my $failedMod = undef;
        next unless(skittlesMatchNick($s->{'nicks'}, $context->{'nick'}));

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

        if($sayit)
        {
            my $replybase = poolNext($s->{'pool'}); # Grab the next reply in the pool for this set

            my $reply = $replybase;
            for my $key (keys(%gSkittlesMods))
            {
                my $mod = $gSkittlesMods{$key};
                while($reply =~ /!\Q$key\E!/)
                {
                    my $replacement = &{ $mod->{'func'} }($context, $key, $mod->{'data'});
                    if(defined($replacement))
                    {
                        $replacement =~ s/^\s+//g;
                        $replacement =~ s/\s+$//g;
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

            $logEntry->{'replybase'} = $replybase;
            $logEntry->{'reply'} = $reply;

            if($reply =~ /^KICKPLZ (.+)$/)
            {
                my ($msg) = ($1);
                ircKick($context, $nick, $msg);
                $logEntry->{'replytype'} = 'kick';
            }
            elsif($reply =~ /^ACTION (.+)$/)
            {
                my($emote) = ($1);
                ircEmote($context, $emote);
                $logEntry->{'replytype'} = 'emote';
            }
            else
            {
                ircSay($context, $reply);
                logMessage($gBotNickname, $reply);
                $logEntry->{'replytype'} = 'say';
            }
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

# -------------------------------------------------------------------------------------------------
# IRC Session Manipulation

sub ircLoad
{
    skittlesStartup();
}

sub ircStartup
{
    my $ircSession = new POE::Component::IRC("IRC");
    my $inlineStates = {
        _start => \&poeSessionStart,
        irc_001 => \&poeSessionConnect,
        irc_join => \&poeSessionJoin,
        irc_msg => \&poeSessionPrivate,
        irc_nick => \&poeSessionNick,
        irc_public => \&poeSessionPublic,
        respond => \&poeRespond,
    };
    POE::Session->create(inline_states => $inlineStates);
}

sub ircDelayResponse
{
    my($context, $response) = @_;

    my $len = length($response->{'text'});
    my $delay =
        1              # time it took Skittles to 'read' the text he is replying to
      + (0.05 * $len); # time it took Skittles to "type" the reply

    if($delay > 4)
    {
        # clamping delay, as it was getting as long as 13 seconds at times
        $delay = 4;
    }

    printf("Delaying type '%s' by %2.2f seconds [%d chars]: %s\n", $response->{'type'}, $delay, $len, $response->{'text'});

    $response->{'delay'} = $delay;
    $response->{'channel'} = $context->{'channel'};
    $context->{'kernel'}->delay(respond => $delay, $response);
}

sub ircEmote
{
    my($context, $text) = @_;
    my $response = {
        type => 'emote',
        text => $text,
    };
    ircDelayResponse($context, $response);
}

sub ircKick
{
    my($context, $nick, $text) = @_;
    my $response = {
        type => 'kick',
        nick => $nick,
        text => $text,
    };
    ircDelayResponse($context, $response);
}

sub ircSay
{
    my($context, $text) = @_;
    my $response = {
        type => 'say',
        text => $text,
    };
    ircDelayResponse($context, $response);
}

sub ircTell
{
    my($context, $nick, $text) = @_;
    my $response = {
        type => 'tell',
        nick => $nick,
        text => $text,
    };
    ircDelayResponse($context, $response);
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

