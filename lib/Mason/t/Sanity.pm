package Mason::t::Sanity;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_ok : Test(1) {
    ok( 1, '1 is ok' );
}

1;
