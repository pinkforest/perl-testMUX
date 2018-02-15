#!/usr/bin/perl

package testMUX;

use strict;
use warnings;

use Time::HiRes;
use Socket qw(SOL_SOCKET SO_REUSEADDR PF_INET SOCK_STREAM);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use IO::Epoll;
use Data::Dumper;
use bytes;

require Exporter;
my @ISA = qw(Exporter);
my @EXPORT = qw();

##################
# Main [0] array
use constant {
    OBJ_POLL        => 0x00,
    DEBUG_LVL       => 0x01,
    DEBUG_FNC       => 0x02,

    MAP_HANDLER_ID  => 0x04,
    MAP_HANDLER_KEY => 0x05,
    BUF_DELETES     => 0x06,
    MAP_NICK        => 0x07,
    IDX_HANDLERS    => 0x08,
    MAP_OPTS        => 0x09,
    MAP_TMOUTS      => 0xA0,

    #### FNOs Data Array
    OBJ_FD       => 0x00,
    OBJ_STACK    => 0x01,
    T_PARENTS    => 0x02,
    T_BABIES     => 0x03,
    T_NICK       => 0x04,
    T_TMOUT      => 0x05,

    DATA_IDX_MIN => 0x06,

    _DEBUG       => 1
};

sub __debug($$) {
    my $self = shift;

    return if !ref($self->[0][DEBUG_FNC]);

    $self->[0][DEBUG_FNC](@_);

}

sub sendParent($$$$$) {
    my ($self, $_fno, $_code, $_data) = (@_);

    if ( defined ( $self->[$_fno][T_PARENTS] ) ) {
        foreach my $_parent (keys %{$self->[$_fno][T_PARENTS]}) {

            my ($_hook, $_func) = ($self->[$_fno][T_PARENTS]{$_parent}->[0],
                                   $self->[$_fno][T_PARENTS]{$_parent}->[1]);
            $_hook->$_func($_parent, $_fno, $_code, $_data);
        }
        return(1);
    }

    $self->__debug(5,$_fno,__PACKAGE__.':'.__LINE__.'-_sendParent() - ERROR no T_PARENT defined to return -> '.
		   $_code.
		   '::'.
		   $_data);

    return ( 0 );
}

sub hookParent($$$$) {
    my ($self, $_fno, $_parent, $_hook, $_func) = (@_);

    $self->__debug(5,$_fno, __PACKAGE__.
                   ':'.__LINE__.
                   '-_hookParent(_fno='.$_fno.', _parent='.$_parent.', _hook='.$_hook.', _func='.$_func.')');

    $self->[$_fno][T_PARENTS]{$_parent} = [$_hook, $_func];

}

sub unhookParent($$$) {
    my ($self, $_fno, $_parent) = (@_);

    $self->__debug(5,$_fno, __PACKAGE__.':'.__LINE__.'-_unhookParent(_fno='.$_fno.', _parent='.
                   $_parent.') current -> ['.
                   (defined ( $self->[$_fno][T_PARENTS]{$_parent} ) ?
                    join(", ", @{$self->[$_fno][T_PARENTS]{$_parent}}) : 'NONE' ).']');

    my $_b_arref;

    if ( defined ( $self->[$_fno][T_PARENTS]{$_parent} ) ) {
        $_b_arref = [$_parent, $self->[$_fno][T_PARENTS]{$_parent}[0], $self->[$_fno][T_PARENTS]{$_parent}[1]];

        $self->[$_fno][T_PARENTS]{$_parent} = undef;
        delete $self->[$_fno][T_PARENTS]{$_parent};

        return $_b_arref;
    }

    return(undef);
}

sub unhookParents($$) {
    my ($self, $_fno) = (@_);

    $self->__debug(5,$_fno, __PACKAGE__.':'.__LINE__.'-_unhookParents(_fno='.$_fno.') current -> ['.
                   ( defined ( $self->[$_fno][T_PARENTS] ) ?
                     join(", ", keys %{$self->[$_fno][T_PARENTS]}) : 'NONE' ).']');

    my $_unhooks;

    if ( defined ( $self->[$_fno][T_PARENTS] ) ) {
        foreach my $_parent ( keys %{$self->[$_fno][T_PARENTS]} ) {
            push(@{$_unhooks}, $self->unhookParent($_fno, $_parent));
        }
    }

    return $_unhooks;
}

sub hookBaby($$$$$) {
    my ($self, $_fno, $_baby, $_hook, $_func) = (@_);

    $self->__debug(5,$_fno, __PACKAGE__.
                   ':'.__LINE__.
                   '-_hookBaby(_fno='.$_fno.', _baby='.$_baby.', _hook='.$_hook.', _func='.$_func.')');

    $self->[$_fno][T_BABIES]{$_baby} = [$_hook, $_func];
}

sub unhookBaby($$$) {
    my ($self, $_fno, $_baby) = (@_);

    $self->__debug(5,$_fno, __PACKAGE__.':'.__LINE__.'-_unhookBaby(_fno='.$_fno.', _baby='.$_baby.') current -> ['.
                   ( defined ( $self->[$_fno][T_BABIES]{$_baby} ) ?
                     join(", ", @{$self->[$_fno][T_BABIES]{$_baby}}) : 'NONE' ).']');

    my $_b_arref;

    if ( defined ( $self->[$_fno][T_BABIES]{$_baby} ) ) {
        $_b_arref = [$_baby, $self->[$_fno][T_BABIES]{$_baby}->[0], $self->[$_fno][T_BABIES]{$_baby}->[1]];

	$self->[$_fno][T_BABIES]{$_baby} = undef;
        delete $self->[$_fno][T_BABIES]{$_baby};

	return $_b_arref;
    }

    return(undef);

}

sub unhookBabies($$) {
    my ($self, $_fno) = (@_);

    $self->__debug(5,$_fno, __PACKAGE__.':'.__LINE__.'-_unhookBabies(_fno='.$_fno.') current -> ['.
                   ( defined ( $self->[$_fno][T_BABIES] ) ?
                     join(", ", keys %{$self->[$_fno][T_BABIES]}) : 'NONE' ).']');

    my $_unhooks;

    if ( defined ( $self->[$_fno][T_BABIES] ) ) {
        foreach my $_baby ( keys %{$self->[$_fno][T_BABIES]} ) {
            push(@{$_unhooks}, $self->unhookBaby($_fno, $_baby));
        }
    }

    return $_unhooks;
}

sub babies($$) {
    my ($self, $_fno) = (@_);

    return ( $self->[$_fno][T_BABIES] );
}

sub parents($$) {
    my ($self, $_fno) = (@_);

    return ( $self->[$_fno][T_PARENTS] );
}

sub nicks($) {
    my $self = shift;
    
    return ( $self->[0][MAP_NICK] );
}

sub mNick($$$) {
    my ($self, $_fno, $_nick) = (@_);

    return 0 if defined ( $self->[0][MAP_NICK]{$_nick} );

    if ( defined ( $self->[$_fno][T_NICK] ) ) {
	$self->[0][MAP_NICK]{$self->[$_fno][T_NICK]} = undef;
	delete $self->[0][MAP_NICK]{$self->[$_fno][T_NICK]};
    }

    $self->[$_fno][T_NICK]       = $_nick;
    $self->[0][MAP_NICK]{$_nick} = $_fno;

    return(1);
}

sub mTimeout($$$$$) {
    my ($self, $_tmout, $_key, $_fno, $_obj, $_func) = (@_);
    my $_t = time();

    $self->__debug(5, $_fno, __PACKAGE__.':'.__LINE__.'-mTimeout(_tmout='.$_tmout.', _key='.$_key.', _fno='.$_fno.', _obj='.$_obj.', _func='.$_func.')');

    $self->[0][MAP_TMOUTS]{$_fno}{$_key} = [ ($_t+$_tmout), $_tmout, $_obj, $_func ];

}

sub mOUT($$$) {
    my ($self, $_fno, $_mbit) = (@_);

    $self->__debug(5, __PACKAGE__.':'.__LINE__.' mOUT['.$_fno.', '.$_mbit.']');

    IO::Epoll::epoll_ctl($self->[0][OBJ_POLL], EPOLL_CTL_MOD, $_fno, ( $_mbit ? EPOLLERR|EPOLLIN|EPOLLOUT : EPOLLERR|EPOLLIN ));

    return(0);
}

sub add($$$$) {
    my ($self, $_stack_obj, $_nfd, $_fno) = (@_);

    $self->__debug(5, $_fno, __PACKAGE__.':'.__LINE__.'-add('.$_fno.')');

    $self->[$_fno][OBJ_FD]    = $_nfd;
    $self->[$_fno][OBJ_STACK] = $_stack_obj;

    IO::Epoll::epoll_ctl($self->[0][OBJ_POLL], EPOLL_CTL_ADD, $_fno, EPOLLERR|EPOLLIN);

    return(0);
}

sub del($$) {
    my ($self, $_fno) = (@_);

    my $_parents;

    $self->__debug(5, $_fno,  __PACKAGE__.':'.__LINE__.'-del('.$_fno.')');

    ###################################
    # Clear parent associations if any
    $_parents = $self->unhookParents($_fno);

    ###############################################################
    # $_parent 0 -> Baby FNO, 1 -> Hook(Ref-Obj), 2-> Func(String)
    if ( defined ( $_parents ) ) {
	my $_pc = 0;
	foreach my $_parent (@{$_parents}) {
	    $_pc++;
	    
	    $self->unhookBaby($_parent->[0], $_fno);
	    $self->__debug(2, $_fno, 'unhookBaby() on Parent<'.$_parent->[0].'> OK.');
	}
	$self->__debug(2, $_fno, 'This baby had '.$_pc.' parents.');
    }
    else {
	$self->__debug(2, $_fno, 'No parent(s)');
    }

    my $_babies;

    ###################################
    # Clear baby associations if any
    $_babies = $self->unhookBabies($_fno);

    if ( defined ( $_babies ) ) {
	my $_bc = 0;
	foreach my $_baby (@{$_babies}) {
	    $_bc++;
	    
	    $self->unhookParent($_baby->[0], $_fno);
	    $self->__debug(2, $_fno, 'unhookParent() on Baby<'.$_baby->[0].'> OK.');

	    if ( ! defined ( $self->[$_baby->[0]][T_NICK] ) ) {
		push(@{$self->[0][BUF_DELETES]}, $_baby->[0]);
	    }
	}
	$self->__debug(2, $_fno, 'This parent had '.$_bc.' babies.');
    }
    else {
	$self->__debug(2, $_fno, 'No baby(s)');
    }

    IO::Epoll::epoll_ctl($self->[0][OBJ_POLL], EPOLL_CTL_DEL, $_fno, 0);

    close($self->[$_fno][OBJ_FD]);

    my $_id;


    $self->[$_fno][OBJ_STACK]->myID();

    if ( defined ( $self->[$_fno][T_NICK] ) ) {
	$self->[0][MAP_NICK]{$self->[$_fno][T_NICK]} = undef;
	delete $self->[0][MAP_NICK]{$self->[$_fno][T_NICK]};
    }

    if ( defined ( $_id ) && $_id >= DATA_IDX_MIN ) {
	$self->[$_fno][$_id] = undef;
	delete $self->[$_fno][$_id];
    }

    $self->[$_fno] = undef;
    delete $self->[$_fno];

    return(0);
}

sub setCallback($$$$) {
    my ($self, $_fno, $_parent, $_func) = (@_);

    return if !defined($_parent) || !defined($_func);

    $self->__debug(5,$_fno, __PACKAGE__.
                   ':'.__LINE__.
                   '-__setCallback(_fno='.$_fno.', _parent='.$_parent.', _func='.$_func.')');

    $self->[$_fno][T_PARENTS]{$_parent}[1] = $_func;

}


sub setHandler($$$$) {
    my ($self, $_key, $_handler_obj, $_id) = (@_);

    $self->__debug(0, 0, __PACKAGE__.':'.__LINE__.'-setHandler('.$_key.') id<'.$_id.'> handler_obj=<'.$_handler_obj.'>');

    $self->[0][MAP_HANDLER_KEY]{$_key} = [$_handler_obj, $_id];
    $self->[0][MAP_HANDLER_ID][$_id]   = [$_handler_obj, $_key];

    eval {
	$_handler_obj->myID($_id);
    };
    if ( $@ ) {
	$self->__debug(0, 0, __PACKAGE__.':'.__LINE__.'-setHandler('.$_key.') id<'.$_id.'> handler_obj=<'.$_handler_obj.'> - ERROR: Attempt to myID('.$_id.') failed: '.$@);
    }

    return(0);
}

sub getHandlerId_key($$) {
    my ($self, $_key) = (@_);

    $self->__debug(0, 0, __PACKAGE__.':'.__LINE__.'-getHandlerId_key('.$_key.')');

    return ( defined ( $self->[0][MAP_HANDLER_KEY]{$_key} ) ? $self->[0][MAP_HANDLER_KEY]{$_key}[1] : undef );
}

sub getHandlerObj_key($$) {
    my ($self, $_key) = (@_);

    $self->__debug(0, 0, __PACKAGE__.':'.__LINE__.'-getHandlerObj_key('.$_key.')');

    return ( defined ( $self->[0][MAP_HANDLER_KEY]{$_key} ) ? $self->[0][MAP_HANDLER_KEY]{$_key}[0] : undef );
}

sub getHandlerObj_id($$) {
    my ($self, $_id) = (@_);

    $self->__debug(0, 0, __PACKAGE__.':'.__LINE__.'-getHandlerObj_id('.$_id.')');

    return ( defined ( $self->[0][MAP_HANDLER_ID][$_id] ) ? $self->[0][MAP_HANDLER_ID][$_id][0] : undef );
}

sub _newHandlerKey($) {
    my $self = shift;

    if ( ! defined ( $self->[0][IDX_HANDLERS] ) ) {
	$self->[0][IDX_HANDLERS] = DATA_IDX_MIN;
    }

    return $self->[0][IDX_HANDLERS]++;
}

sub addHandler($$$) {
    my ($self, $_key, $_l_opts) = (@_);
    my $_handler;

    if ( defined ( $_l_opts ) ) {
	$_l_opts->{'tmux'} = $self->[0][MAP_OPTS]{'tmux'};
    }

    $self->__debug(0, 0, __PACKAGE__.':'.__LINE__.'-addHandler('.$_key.')');

    return(undef) if defined ( $self->[0][MAP_HANDLER_KEY]{$_key} );

    if ( $_key =~ /[^A-Za-z0-9:]/ ) {
	$self->__debug(0, 0, 'Attempt to add bogus Handler<'.$_key.'>');
	return(undef);
    }

    $self->__debug(5, 0, 'Loading the Handler<'.$_key.'> package');

    eval {
        require $_key.'.pm';
    };
    if ( $@ ) {
	$self->__debug(0, 0, 'Load package for Handler<'.$_key.'> failed: '.$@);
	return(undef);
    }

    eval {
	$_handler = $_key->new( ( defined ( $_l_opts ) ? $_l_opts : $self->[0][MAP_OPTS]) );
    };
    if ( $@ ) {
	$self->__debug(0, 0, 'Attempt to initialize Handler<'.$_key.'> failed '.$@);
    }

    my $_id = $self->_newHandlerKey();
    $self->__debug(0, 0, __PACKAGE__.':'.__LINE__.'-addHandler('.$_key.') -> id<'.$_id.'>');

    $self->setHandler($_key, ( defined ( $_handler ) ? $_handler : undef ), $_id );

    return($_handler);
}

sub addTCPConnector($$$$) {
    my ($self, $_stack, $_naddr, $_nport) = (@_);
    my $_stack_obj;

    my $_nfd;
    my $si = socket($_nfd, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
 
    my $flags = fcntl($_nfd, F_GETFL, 0);
    $flags = 0 if defined($flags) || $flags==-1;

    my $fc = fcntl($_nfd, F_SETFL, $flags | O_NONBLOCK);
    
    $fc = connect($_nfd, Socket::sockaddr_in($_nport, Socket::inet_aton($_naddr)));

    my $_nfno = fileno($_nfd);

    if ( ref ( $_stack ) eq '' ) {

	$_stack_obj = $self->getHandlerObj_key( $_stack );

	if ( ! defined ( $_stack_obj ) ) {
	    my $_nstack = $self->addHandler($_stack);
	    
	    if ( ! defined ( $_nstack ) ) {
		$self->__debug(0, 0, 'addTCPConnector: Failed to addHandler<'.$_stack.'>');
		return(undef);
	    }
	    $_stack_obj = $_nstack;
	}
    }
    # ++TODO:Add capability check can(handle_in)
    else {
	$_stack_obj = $_stack;
    }

    # ++TODO:Check (&create) hook return.
#    eval {
	$_stack_obj->hookTCPConnector($_nfd, $_nfno);
#    };
#    if ( $@ ) {
#	$self->__debug(0, '/**** BUG<'.__LINE__.'> Stack Object '.$_stack_obj.' hookTCPConnector() = '.$@);
#	$_nfd=undef;
#	return(-1);
#    }

    $self->add($_stack_obj, $_nfd, $_nfno);

    ###############################################################################
    # Non-blocking connection establishment needs to be determined if we can write.
    $self->mOUT($_nfno, 1);

    return($_nfno);
}

sub adopt($$$$) {
    my ($self, $_orig_fno, $_dest_fno, $_hook, $_func) = (@_);

    $self->__debug(5, $_orig_fno, __PACKAGE__.':'.__LINE__.'-adopt('.$_orig_fno.', '.$_dest_fno.', '.$_hook.', '.$_func.')');

    $self->hookParent($_dest_fno, $_orig_fno, $_hook, $_func);
    $self->hookBaby($_orig_fno, $_dest_fno, $self->[$_dest_fno][OBJ_STACK], $_func);

    return(0);
}

sub addTCPListener($$$$) {
    my ($self, $_stack, $_naddr, $_nport) = (@_);

    my ($_stack_obj, $_nfd, $fc);

    $fc = socket($_nfd, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
    $fc = setsockopt($_nfd, SOL_SOCKET, SO_REUSEADDR, 1); 
    my $flags = fcntl($_nfd, F_GETFL, 0);
    $flags = 0 if defined($flags) || $flags==-1;

    $fc = fcntl($_nfd, F_SETFL, O_NONBLOCK);

    my $sin = Socket::sockaddr_in($_nport,Socket::inet_aton($_naddr));

    $fc = bind($_nfd, $sin);
    $fc = listen($_nfd, 100);
    $fc = fcntl($_nfd, F_SETFL, O_NONBLOCK);

    my $_fno = fileno($_nfd);

    if ( ref ( $_stack ) eq '' ) {

	$_stack_obj = $self->getHandlerObj_key( $_stack );

	if ( ! defined ( $_stack_obj ) ) {
	    my $_nstack = $self->addHandler($_stack);
	    
	    if ( ! defined ( $_nstack ) ) {
		$self->__debug(0, 0, 'addTCPConnector: Failed to addHandler<'.$_stack.'>');
		return(undef);
	    }
	    $_stack_obj = $_nstack;
	}
    }
    # ++TODO:Add capability check can(handle_in)
    else {
	$_stack_obj = $_stack;
    }

    $_stack_obj->hookTCPListener($_nfd, $_fno);

    $self->add($_stack_obj, $_nfd, $_fno);

    return($_fno);
}

sub run {
    my $self = shift;

    while(1) {

	my $_evs = epoll_wait($self->[0][OBJ_POLL], 15000, 15000);
	my $_evc = scalar(@{$_evs});

	$self->__debug(5, '__RUN<'.__LINE__.'> epoll_wait[OK] EventCount = '.$_evc);

	for(my $_ei = 0;$_ei <= ($_evc-1);$_ei++) {
	    my $_eventObj = $_evs->[$_ei];
	    
	    my $_evFno  = $_eventObj->[0];
	    my $_evBits = $_eventObj->[1];
	    
	    if ( $_evBits & EPOLLIN ) {
		$self->__debug(3, '__RUN<'.__LINE__.'> Got EPOLLIN<'.$_evFno.'>...');

		my $r = $self->[$_evFno][OBJ_STACK]->handler_in($_evFno);
		next if $r != 0;
	    }
	    if ( $_evBits & EPOLLOUT ) {
	        $self->__debug(3, '__RUN<'.__LINE__.'> Got EPOLLOUT<'.$_evFno.'>...');

		my $r = $self->[$_evFno][OBJ_STACK]->handler_out($_evFno);
		next if $r != 0;
	    }
	    if ( $_evBits & EPOLLERR ) {
		$self->__debug(3, '__RUN<'.__LINE__.'> Got EPOLLERR<'.$_evFno.'>...');

		$self->[$_evFno][OBJ_STACK]->handler_err($_evFno);
	    }
	}

	while ( my $_del = shift(@{$self->[0][BUF_DELETES]}) ) {
	    $self->__debug(3, '__RUN<'.__LINE__.'> Clearing orphan(?) '.$_del);
	    $self->del($_del);
	}
    }
}

sub new {
    my $class = shift;
    my ($opts) = shift;
    my $self = [];
    bless $self, $class;

    $self->[0][DEBUG_LVL] = ( defined($opts->{'debug'}) ? $opts->{'debug'} : 0 );
    $self->[0][DEBUG_FNC] = ( $self->[0][DEBUG_LVL] > 0 && defined($opts->{'debugFunc'}) ) ? $opts->{'debugFunc'} : undef ;

    $self->[0][OBJ_POLL]  = IO::Epoll::epoll_create(25);

    $opts->{tmux}         = $self;

    $self->[0][MAP_OPTS]  = $opts;

    $self->__debug(2,'__INITIALIZE__','OK');

    return $self;
}

sub VERSION {
    return(1);
}

sub DESTROY {
}

1;
