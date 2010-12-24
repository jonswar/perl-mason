package Mason::t::Errors;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub test_errors : Test(5) {
    my $self = shift;
    $self->test_comp(
        src          => '%my $i = 1;',
        expect_error => qr/% must be followed by whitespace at .* line 1/,
    );
    my $root = $self->{interp}->comp_root->[0];
    $self->test_comp(
        src => '<& /does/not/exist &>',
        expect_error =>
          qr/could not find component for path '\/does\/not\/exist' - component root is \Q[$root]\E/,
    );
    $self->test_comp(
        src          => '<%',
        expect_error => qr/'<%' without matching '%>'/,
    );
    $self->test_comp(
        src          => '<%init>',
        expect_error => qr/<%init> without matching <\/%init>/,
    );
    $self->test_comp(
        src          => '<%method>',
        expect_error => qr/method block requires a name/,
    );
}

1;
