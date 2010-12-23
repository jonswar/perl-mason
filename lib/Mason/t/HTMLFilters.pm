package Mason::t::HTMLFilters;
use strict;
use warnings;
use base qw(Mason::Test::Class);
use Test::More;
use Method::Signatures::Simple;

sub test_html_filters : Test(1) {
    my $self = shift;
    $self->test_comp( component => '<% "<a>" | HTML %>', expect => '&lt;a&gt;' );
}

1;
