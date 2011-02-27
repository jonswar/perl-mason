package Mason::t::HTMLFilters;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_html_filters : Tests {
    my $self = shift;
    $self->setup_interp( plugins => [ '@Default', 'HTMLFilters' ] );
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
