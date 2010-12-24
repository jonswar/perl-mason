package Mason::t::Skel;
use Test::More;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub test_ : Test(1) {
    shift->test_comp(
        src => <<'EOF',
EOF
        expect => <<'EOF',
EOF
    );
}

1;
