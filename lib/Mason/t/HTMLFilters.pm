package Mason::t::HTMLFilters;
use strict;
use warnings;
use base qw(Mason::Test::Class);
use Test::More;

sub test_html_filters : Test(4) {
    my $self = shift;
    $self->{interp} = $self->create_interp( plugins => ['HTMLFilters'] );
    $self->test_comp( src => '<% "<a>" | HTML %>',         expect => '&lt;a&gt;' );
    $self->test_comp( src => '<% "/foo/bar?a=5" | URI %>', expect => '%2Ffoo%2Fbar%3Fa%3D5' );
    $self->test_comp(
        src    => '<% "First\n\nSecond\n\nThird\n\n" | HTMLPara %>',
        expect => "<p>\nFirst\n</p>\n\n<p>\nSecond\n</p>\n\n<p>\nThird</p>\n"
    );
    $self->test_comp(
        src    => '<% "First\n\nSecond\n\nThird\n\n" | NoBlankLines,HTMLPara %>',
        expect => "<p>\nFirst\n</p>\n<p>\nSecond\n</p>\n<p>\nThird</p>\n"
    );
}

1;
