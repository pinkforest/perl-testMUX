#!/usr/bin/perl

use strict;
use warnings;

use testMUX;

use Time::HiRes;

#$|=1;

my $st = [Time::HiRes::gettimeofday];

sub _debug {

    my $et=[Time::HiRes::gettimeofday];
    
    print Time::HiRes::tv_interval($st, $et).' DEBUG='.join(',', @_)."\n";

}

my $mux = testMUX->new({'debug' => 5,
			'debugFunc' => \&_debug });

$mux->addHandler('AdminStack', {'debug' => 5,
				'debugFunc' => \&_debug,
				'MongoAuthenticateHost' => '127.0.0.1',
				'MongoAuthenticatePort'  => 27017});

$mux->addTCPListener('AdminStack', '127.0.0.1', 4242);

$mux->run;


