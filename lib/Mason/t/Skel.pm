package Mason::t::Skel;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_ : Test(1) {
    my $self = shift;
    $self->test_comp(
        src => <<'EOF',
EOF
        expect => <<'EOF',
EOF
    );
}

1;
