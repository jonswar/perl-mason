package Mason::t::Cache;
use Test::Class::Most parent => 'Mason::Test::Class';

__PACKAGE__->default_plugins( [ '@Default', 'Cache' ] );

sub test_cache_defaults : Tests {
    my $self = shift;
    $self->run_test_in_comp(
        path => '/cache/defaults.mc',
        test => sub {
            my $comp = shift;
            is( $comp->cache->label,     'File',             'cache->label' );
            is( $comp->cache->namespace, $comp->cmeta->path, 'cache->namespace' );
        }
    );
}

sub test_cache_method : Tests {
    my $self = shift;
    $self->test_comp(
        path => '/cache.mc',
        src  => '
<%class>
has ' count ' => ( default => 0 );

</%class>

<%method getset ($key)>
<%perl>$.count($.count+1);</%perl>
<% $.cache->compute($key, sub { $key . $.count }) %>
</%method>

namespace: <% $.cache->namespace %>
<% $.getset("foo") %>
<% $.getset("bar") %>
<% $.getset("bar") %>
<% $.getset("foo") %>
',
        expect => '
namespace: /cache.mc
foo1

bar2

bar2

foo1
',
    );
}

sub test_cache_filter : Tests {
    my $self = shift;

    $self->test_comp(
        src => '
% my $i = 1;
% foreach my $key (qw(foo bar)) {
% $.Repeat(3), $.Cache($key) {{
i = <% $i++ %>
% }}
% }
',
        expect => '
i = 1
i = 1
i = 1
i = 2
i = 2
i = 2
',
    );

    $self->test_comp(
        src => '
% my $i = 1;
% foreach my $key (qw(foo foo)) {
% $.Cache($key), $.Repeat(3) {{
i = <% $i++ %>
% }}
% }
',
        expect => '
i = 1
i = 2
i = 3
i = 1
i = 2
i = 3
'
    );
}
