package Mason::t::Request;
use Log::Any::Adapter;
use Test::More;
use Test::Log::Dispatch;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub _get_current_comp_class {
    my $m = shift;
    return $m->_current_comp_class;
}

sub test_cache : Test(1) {
    my $self = shift;
    $self->test_comp(
        path => '/cache.m',
        src  => '
<%shared>
$.count => 0
</%shared>

<%method getset ($key)>
<%perl>$.count($.count+1);</%perl>
<% $m->cache->compute($key, sub { $key . $.count }) %>
</%method>

namespace: <% $m->cache->namespace %>
<% $.getset("foo") %>
<% $.getset("bar") %>
<% $.getset("bar") %>
<% $.getset("foo") %>
',
        expect => '
namespace: /cache.m
foo1

bar2

bar2

foo1
',
    );
}

sub test_comp_exists : Test(1) {
    my $self = shift;

    $self->add_comp( path => '/comp_exists/one.m', src => 'hi' );
    $self->test_comp(
        path => '/comp_exists/two.m',
        src  => '
% foreach my $path (qw(/comp_exists/one.m /comp_exists/two.m /comp_exists/three.m one.m two.m three.m)) {
<% $path %>: <% $m->comp_exists($path) ? "yes" : "no" %>
% }
',
        expect => '
/comp_exists/one.m: yes
/comp_exists/two.m: yes
/comp_exists/three.m: no
one.m: yes
two.m: yes
three.m: no
',
    );
}

sub test_current_comp_class : Test(1) {
    shift->test_comp(
        path   => '/current_comp_class.m',
        src    => '<% ' . __PACKAGE__ . '::_get_current_comp_class($m)->cmeta->path %>',
        expect => '/current_comp_class.m'
    );
}

sub test_count : Test(3) {
    my $self = shift;
    $self->setup_dirs;
    $self->add_comp( path => '/count.m', src => 'count=<% $m->count %>' );
    is( $self->{interp}->run('/count.m')->output, "count=0" );
    is( $self->{interp}->run('/count.m')->output, "count=1" );
    is( $self->{interp}->run('/count.m')->output, "count=2" );
}

sub test_log : Test(2) {
    my $self = shift;
    my $log = Test::Log::Dispatch->new( min_level => 'debug' );
    Log::Any::Adapter->set( { category => 'Mason::Component::log::one.m', lexically => \my $lex },
        'Dispatch', dispatcher => $log );
    $self->add_comp( path => '/log/one.m', src => '% $m->log->info("message one")' );
    $self->add_comp( path => '/log/two.m', src => '% $m->log->info("message two")' );
    $self->run_test_in_comp(
        path => '/log.m',
        test => sub {
            my $comp = shift;
            my $m    = $comp->m;
            $m->comp('/log/one.m');
            $m->comp('/log/two.m');
            $log->contains_ok("message one");
            $log->does_not_contain_ok("message two");
        },
    );
}

sub test_page : Test(1) {
    my $self = shift;
    $self->add_comp( path => '/page/other.mi', src => '<% $m->page->cmeta->path %>' );
    $self->test_comp(
        path   => '/page/first.m',
        src    => '<% $m->page->cmeta->path %>; <& other.mi &>',
        expect => '/page/first.m; /page/first.m'
    );
}

sub test_subrequest : Test(2) {
    my $self = shift;
    $self->add_comp(
        path => '/subreq/other.m',
        src  => '
<% $m->page->cmeta->path %>
<% $m->request_path %>
<% join(", ", @{ $m->request_args }) %>
',
    );
    $self->test_comp(
        path => '/subreq/go.m',
        src  => '
This should not get printed.
<%perl>$m->go("/subreq/other.m", foo => 5);</%perl>',
        expect => '
/subreq/other.m
/subreq/other.m
foo, 5
',
    );
    $self->test_comp(
        path => '/subreq/visit.m',
        src  => '
begin
<%perl>$m->visit("/subreq/other.m", foo => 5);</%perl>
end
',
        expect => '
begin
/subreq/other.m
/subreq/other.m
foo, 5
end
',
    );

}

1;
