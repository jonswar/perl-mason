package Mason::t::Errors;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub test_errors : Test(10) {
    my $self = shift;
    $self->test_comp(
        component    => '%my $i = 1;',
        expect_error => qr/% must be followed by whitespace at .* line 1/,
    );
    $self->test_comp(
        component    => '<& /does/not/exist &>',
        expect_error => qr/could not find component for path/,
    );
    $self->test_comp(
        component    => '<%',
        expect_error => qr/'<%' without matching '%>'/,
    );
    $self->test_comp(
        component    => '<%init>',
        expect_error => qr/<%init> without matching <\/%init>/,
    );
    $self->test_comp(
        component    => '<%method>',
        expect_error => qr/method block requires a name/,
    );
}

1;
