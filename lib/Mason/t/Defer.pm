package Mason::t::Defer;
use Test::More;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub test_defer : Test(1) {
    my $self = shift;
    $self->{interp} = $self->create_interp( plugins => [ '@Default', 'Defer' ] );
    $self->test_comp(
        src => <<'EOF',
<%class>
my ($title, $subtitle);
</%class>

Title is <% $m->defer(sub { $title }) %>

% $.Defer {{
Subtitle is <% $subtitle %>
% }}

<%perl>
$title = 'foo';
$subtitle = 'bar';
</%perl>
EOF
        expect => <<'EOF',
Title is foo

Subtitle is bar
EOF
    );
}

1;
