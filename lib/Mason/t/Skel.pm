package Mason::t::Skel;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub test_ : Test(1) {
    shift->test_comp(
        component => <<'EOF',
EOF
        expect => <<'EOF',
EOF
    );
}
