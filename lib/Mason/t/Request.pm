package Mason::t::Request;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub _get_current_comp {
    my $m = shift;
    return $m->current_comp;
}

sub test_current_comp : Test(1) {
    shift->test_comp(
        path      => '/current_comp.m',
        component => '<% ' . __PACKAGE__ . '::_get_current_comp($m)->comp_path %>',
        expect    => '/current_comp.m'
    );
}

1;
