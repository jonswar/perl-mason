package Mason::t::Skel;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_ : Tests {
    my $self = shift;
    $self->test_comp(
        src => '
',
        expect => '
',
    );
}

1;
