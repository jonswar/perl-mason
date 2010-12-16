package Mason::t::Request;
use Test::More;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub _get_current_comp_class {
    my $m = shift;
    return $m->current_comp_class;
}

sub test_current_comp_class : Test(1) {
    shift->test_comp(
        path      => '/current_comp_class.m',
        component => '<% ' . __PACKAGE__ . '::_get_current_comp_class($m)->comp_path %>',
        expect    => '/current_comp_class.m'
    );
}

sub test_count : Test(3) {
    my $self = shift;
    $self->setup_dirs;
    $self->add_comp( path => '/count.m', component => 'count=<% $m->count %>' );
    is( $self->{interp}->srun('/count'), "count=0" );
    is( $self->{interp}->srun('/count'), "count=1" );
    is( $self->{interp}->srun('/count'), "count=2" );
}

sub test_page : Test(1) {
    my $self = shift;
    $self->add_comp( path => '/page/other.mi', component => '<% $m->page->comp_title %>' );
    $self->test_comp(
        path      => '/page/first.m',
        component => '<% $m->page->comp_title %>; <& other.mi &>',
        expect    => '/page/first.m; /page/first.m'
    );
}

1;
