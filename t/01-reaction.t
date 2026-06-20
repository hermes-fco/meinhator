use strict;
use warnings;
use Test::More;

# ── Mock Mojo::SlackRTM ────────────────────────────────────────────
# Installed in %INC so `use Mojo::SlackRTM` inside app.pl finds it.
BEGIN { $INC{'Mojo/SlackRTM.pm'} = 'mocked-in-test' }

{
    package Mojo::SlackRTM;
    use strict;
    use warnings;

    our ($INSTANCE, @REACTIONS_CALLS);

    sub new {
        my ($class, %args) = @_;
        @REACTIONS_CALLS = ();
        $INSTANCE = bless {
            token  => $args{token},
            events => {},
        }, $class;
        return $INSTANCE;
    }

    sub on {
        my ($self, $event, $cb) = @_;
        $self->{events}{$event} = $cb;
    }

    sub find_user_name {
        my ($self, $id) = @_;
        my $map = {
            'U111' => 'john',
            'U222' => 'jane',
            'U333' => 'bob',
        };
        return $map->{$id} // "user-$id";
    }

    sub call_api {
        my ($self, $method, $args) = @_;
        if ($method eq 'reactions.add') {
            push @REACTIONS_CALLS, $args;
        }
    }

    sub start { }  # no-op — don't connect to Slack

    sub log {
        my $self = shift;
        return Mojo::SlackRTM::_Log->new;
    }

    sub _trigger {
        my ($self, $event, $data) = @_;
        if (my $cb = $self->{events}{$event}) {
            $cb->($self, $data);
        }
        return $self;
    }

    package Mojo::SlackRTM::_Log;
    sub new  { bless {}, shift }
    sub debug { }
}

# ── Helpers ─────────────────────────────────────────────────────────

sub load_app {
    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    do './app.pl';
    return $Mojo::SlackRTM::INSTANCE;
}

my $default_event = {
    channel => 'C001',
    user    => 'U999',
    ts      => '1234567890.000001',
    text    => 'hello world',
};

# ════════════════════════════════════════════════════════════════════
# Test 1: No filters → reacts to EVERY message
# ════════════════════════════════════════════════════════════════════
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    local $ENV{SLACK_REACTION} = 'thumbsup';
    delete local $ENV{SLACK_USER};
    delete local $ENV{SLACK_USER_ID};
    delete local $ENV{SLACK_LOOKFOR};

    my $bot = load_app();

    $bot->_trigger(message => { %$default_event, text => 'any random text' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'no filters → reacts to any message';
    is $Mojo::SlackRTM::REACTIONS_CALLS[0]{name}, 'thumbsup',
        'no filters → uses configured SLACK_REACTION';
}

# ════════════════════════════════════════════════════════════════════
# Test 2: SLACK_USER_ID alone — works independently
# ════════════════════════════════════════════════════════════════════
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    local $ENV{SLACK_REACTION} = '100';
    delete local $ENV{SLACK_USER};
    local $ENV{SLACK_USER_ID}  = 'U111';
    delete local $ENV{SLACK_LOOKFOR};

    my $bot = load_app();

    # ID matches
    $bot->_trigger(message => { %$default_event, user => 'U111', text => 'hi' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_USER_ID matches → reacts';

    # ID does NOT match → no react
    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => { %$default_event, user => 'U999', text => 'random' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 0,
        'SLACK_USER_ID does not match → no react';

    # Case insensitive
    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => { %$default_event, user => 'u111', text => 'hi' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_USER_ID case insensitive';
}

# ════════════════════════════════════════════════════════════════════
# Test 3: SLACK_LOOKFOR alone — works independently
# ════════════════════════════════════════════════════════════════════
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    local $ENV{SLACK_REACTION} = '100';
    delete local $ENV{SLACK_USER};
    delete local $ENV{SLACK_USER_ID};
    local $ENV{SLACK_LOOKFOR}  = 'pizza';

    my $bot = load_app();

    # Keyword matches
    $bot->_trigger(message => { %$default_event, text => 'who wants pizza?' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_LOOKFOR matches → reacts';

    # Keyword does NOT match → no react
    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => { %$default_event, text => 'random talk' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 0,
        'SLACK_LOOKFOR does not match → no react';

    # Word boundary
    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => { %$default_event, text => 'pizzaria is great' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 0,
        'SLACK_LOOKFOR respects word boundary';
}

# ════════════════════════════════════════════════════════════════════
# Test 4: SLACK_USER set → only reacts when conditions match
# ════════════════════════════════════════════════════════════════════

# 4a: SLACK_USER matches user_name
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    local $ENV{SLACK_REACTION} = '100';
    local $ENV{SLACK_USER}     = 'john';
    delete local $ENV{SLACK_USER_ID};
    delete local $ENV{SLACK_LOOKFOR};

    my $bot = load_app();

    $bot->_trigger(message => { %$default_event, user => 'U111', text => 'hi' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_USER matches message author name → reacts';

    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => { %$default_event, user => 'U222', text => 'hi' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 0,
        'SLACK_USER does not match author name → no react';

    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    local $ENV{SLACK_USER} = 'JOHN';
    my $bot2 = load_app();
    $bot2->_trigger(message => { %$default_event, user => 'U111', text => 'hi' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_USER case insensitive name match';
}

# 4b: SLACK_USER matched by @-mention (citated)
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    local $ENV{SLACK_REACTION} = '100';
    local $ENV{SLACK_USER}     = 'bob';
    delete local $ENV{SLACK_USER_ID};
    delete local $ENV{SLACK_LOOKFOR};

    my $bot = load_app();

    $bot->_trigger(message => {
        %$default_event,
        user => 'U222',
        text => 'hey <@U333> what do you think?',
    });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_USER @-mentioned → reacts';

    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => { %$default_event, user => 'U222', text => 'hey there' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 0,
        'SLACK_USER not @-mentioned → no react';
}

# 4c: SLACK_USER matched by literal word in text
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    local $ENV{SLACK_REACTION} = '100';
    local $ENV{SLACK_USER}     = 'john';
    delete local $ENV{SLACK_USER_ID};
    delete local $ENV{SLACK_LOOKFOR};

    my $bot = load_app();

    $bot->_trigger(message => {
        %$default_event,
        user => 'U222',
        text => 'has anyone seen john today?',
    });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_USER found as word in text → reacts';

    # Word boundary — "johnson" should NOT match "john"
    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => {
        %$default_event,
        user => 'U222',
        text => 'meet johnson the new guy',
    });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 0,
        'SLACK_USER respects word boundary — "johnson" ≠ "john"';

    # Case insensitive
    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => {
        %$default_event,
        user => 'U222',
        text => 'Hey JOHN!',
    });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_USER literal match case insensitive';
}

# 4d: SLACK_USER_ID match
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    local $ENV{SLACK_REACTION} = '100';
    local $ENV{SLACK_USER}     = 'someone-else';
    local $ENV{SLACK_USER_ID}  = 'U111';
    delete local $ENV{SLACK_LOOKFOR};

    my $bot = load_app();

    $bot->_trigger(message => { %$default_event, user => 'U111', text => 'hi from john' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_USER_ID matches → reacts';

    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => { %$default_event, user => 'U222', text => 'hi from jane' });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 0,
        'SLACK_USER_ID does not match → no react';
}

# ════════════════════════════════════════════════════════════════════
# Test 5: Regex safety — \Q...\E prevents metacharacter injection
# ════════════════════════════════════════════════════════════════════
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    local $ENV{SLACK_REACTION} = '100';
    local $ENV{SLACK_USER}     = 'john.doe';      # '.' is regex wildcard
    delete local $ENV{SLACK_USER_ID};
    delete local $ENV{SLACK_LOOKFOR};

    my $bot = load_app();

    # Exact match expected
    $bot->_trigger(message => {
        %$default_event,
        user => 'U999',
        text => 'john.doe is online',
    });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'regex-safety: exact username match works';

    # '.' should NOT match arbitrary chars
    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => {
        %$default_event,
        user => 'U999',
        text => 'johnXdoe is online',   # '.' should NOT match 'X'
    });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 0,
        'regex-safety: regex metachar "." does NOT match arbitrary char';
}

# ════════════════════════════════════════════════════════════════════
# Test 6: SLACK_USER + SLACK_LOOKFOR both set
# ════════════════════════════════════════════════════════════════════
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    local $ENV{SLACK_REACTION} = '100';
    local $ENV{SLACK_USER}     = 'john';
    delete local $ENV{SLACK_USER_ID};
    local $ENV{SLACK_LOOKFOR}  = 'pizza';

    my $bot = load_app();

    $bot->_trigger(message => {
        %$default_event,
        user => 'U222',
        text => 'who wants pizza tonight?',
    });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'SLACK_LOOKFOR matches → reacts even when SLACK_USER does not';

    @Mojo::SlackRTM::REACTIONS_CALLS = ();
    $bot->_trigger(message => {
        %$default_event,
        user => 'U222',
        text => 'random chat',
    });
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 0,
        'neither SLACK_USER nor SLACK_LOOKFOR match → no react';
}

# ════════════════════════════════════════════════════════════════════
# Test 7: SLACK_REACTION default
# ════════════════════════════════════════════════════════════════════
{
    local $ENV{SLACK_TOKEN}    = 'xoxb-test';
    delete local $ENV{SLACK_REACTION};
    delete local $ENV{SLACK_USER};
    delete local $ENV{SLACK_USER_ID};
    delete local $ENV{SLACK_LOOKFOR};

    my $bot = load_app();

    $bot->_trigger(message => $default_event);
    is scalar(@Mojo::SlackRTM::REACTIONS_CALLS), 1,
        'default SLACK_REACTION "100" is used';
    is $Mojo::SlackRTM::REACTIONS_CALLS[0]{name}, '100',
        'reaction name is "100"';
}

done_testing;
