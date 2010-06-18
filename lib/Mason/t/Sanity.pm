package Mason::t::Sanity;
use strict;
use warnings;
use Test::More;
use base qw(Test::Class);

sub test_ok : Test(1) {
    ok( 1, '1 is ok' );
}

1;
