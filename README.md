# testMUX

## Purpose

- Perl experimental yet another async event multiplexer (MUX) framework
- Handle any input/output with events seamlessly between via one async mux
- Handle between Linux Epoll, Solaris /dev/poll and FreeBSD kqueue
- Support TCP/UDP Client/Server /IPC::Open3
- Nodularize Client/Server etc as abstracted "Stacks" easily used across
- Example stacks for Mikrotik API, MongoDB and AdminServer

## Warnings

- These modules were created long time ago before there was anything else more elegant
- This is heavily Obsolete for pure event handling, use AnyEvent, Node etc for modern projects
- To store data I used arrays with constants key index in fear of old perl bug where hash searcfh tables leaked memory
- There is absolutely no tests :(

## Main Methods

These are the methods that are called from the script running the event loop

### new()

Create a new event multiplexer object

```
my $mux = testMUX->new({'debug' => 5,
                        'debugFunc' => \&_debug });
```

We refer the object created later as $mux

### run()

Run the event multiplexer after all the top level stacks have been loaded with add*Listener/Connector

```
$mux->run();
```

### addHandler(key, options)

Initialise a stack with identifier key with options
- key: the stackname as literal string
- options: hashtable of options to pass to initialized stack 

A stack initialised can have options to nest and spawn other stacks e.g. MongoClient used for authentication:

```
$mux->addHandler('AdminStack', {'debug' => 5,
                                'debugFunc' => \&_debug,
                                'MongoAuthenticateHost' => '127.0.0.1',
                                'MongoAuthenticatePort'  => 27017});
```

### addTCPListener(stack, address, port)

Initialise a TCP server listen on address and port using a stack previously loaded with addHandler()

- stack: the stackname as literal string
- address: IPv4 address (sorry no IPv6 or hostname resolving)
- port: tcp port

```
$mux->addTCPListener('AdminStack', '127.0.0.1', 4242);
```

## Stack Requirements

Every type of stack has to have certain methods in order to work

## All: new(opts)

When ever new stack is loaded basic options are passed as follows in a hashtable opts:
- debug: level of debug
- debugFunc: debugging function that can be used
- tmux: main mux object access if required

Note: My examples stores all the data under the main mux object as $mux->[fno][key-constant] where the [fno] array is always guaranteed to get cleared. There are cerftainly much better ways to do this and I could have simply used hashtable but old habit of avoiding performance loss and search table memory leaks with old version of perl and strict keying with constants kicked in that does not make too readable code in turn.

```
sub new {
    my $class = shift;
    my ($opts) = shift;
    my $self = [];
    bless $self, $class;

    $self->[DEBUG_LVL]  = ( defined($opts->{'debug'}) ? $opts->{'debug'} : 0 );
    $self->[DEBUG_FNC]  = ( $self->[DEBUG_LVL] > 0 && defined($opts->{'debugFunc'}) ) ? $opts->{'debugFunc'} : undef ;

    $self->[OBJ_TMUX]     = ( defined($opts->{'tmux'}) ? $opts->{'tmux'} : undef );

    $self->__debug(2, 0, 'TMUX<'.__PACKAGE__.'> Reference = '.$self->[OBJ_TMUX]);

    $self->__debug(2, 0, '__INITIALIZE__','OK');

    return $self;
}
```

## All: myID(id)

The set/get method is used to keep track of identifier of stacks

```
sub myID($;$) {
    my ($self, $_id) = (@_);

    if ( defined ( $_id ) ) {
        $self->[SELF_ID] = $_id;
    }

    return($self->[SELF_ID]);
}
```

### TCP Servers: hookTCPListener(fd, fno)

The following gets passed to a method handling new TCP listeners
- fd: socket filehandle
- fno: socket fileno

```
sub hookTCPListener($$) {
    my ($self, $_nfd, $_fno) = (@_);
    $self->[OBJ_TMUX][$_fno][$self->[SELF_ID]] = [];
    my $_d = $self->[OBJ_TMUX][$_fno][$self->[SELF_ID]];

    $self->__debug(5,$_fno, __PACKAGE__.':'.__LINE__.'-_hookTCPListener('.$_fno.') myID = '.$self->[SELF_ID]);
    
    $_d->[T_SERVER_I] = [];
    $_d->[T_SERVER_I][I_SERVER_OBJ] = $_nfd;
}
```

## Stack Methods

These are the methods called from inside of the individual stacks

### addTCPConnector(stack, address, port)

Initialise a TCP Client Stack
- stack: literal string of the stack, will be loaded if not loaded
- address: peer host/server address to connect to
- port; port to connect to

```
my $fno = $self->[OBJ_TMUX]->addTCPConnector('MTikClient', $_host, $_port);
```

We refer the return of this later as fno (File Number)

### sendParent(fno, code, data)

If the server or client stack has created a baby (e.g. client) this method can be used to send code and user data back to parent into the callback set earlier.

```
$self->[OBJ_TMUX]->sendParent($_fno, 0, 'INFO Initiated login request. Waiting for the challenge.');
```

### babies(fno)

### parents(fno)

### nicks()

### mNick(fno)

### mTimeOut(timeout, key, fno, object, func)

### mOUT(fno, bit)

### add(stack, fd, fno)

### del(fno)

### setCallBack(fno, parent, func)

## Internal Methods

These are internal methods within the multiplexer

### hookParent(fno, parent, hook, func)

### unhookParent(fno, parent)

### unhookParents(fno)

### hookBaby(fno, baby, hook, func)

### unhookBaby(fno, baby)

### unhookBabies(fno)

### setHandler(key, handler_object, id)

### getHandlerId_key(key)

### getHandlerObj_key(key)

### adopt(origin_fno, destination_fno, hook, func)




=======
# TMongoClient

I wanted to know how fun it would be to implement a MongoDB wire protocol from scratch :)

Don't use!

