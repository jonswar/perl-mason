package Mason::t::Filters;
use strict;
use warnings;
use base qw(Mason::Test::Class);
use Mason::AdvancedFilter;

sub test_filters : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => '
<%class>
method Upper  () { sub { uc(shift) } }
</%class>

<% $.Upper { %>
Hello World
<% } %>

<% sub { lc(shift) } { %>
Hello World
<% } %>
',
        expect => '
HELLO WORLD
hello world
',
    );
}

sub test_lexical : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
% my $msg = "Hello World";
<% sub { lc(shift) } { %>
<% $msg %>
<% } %>
EOF
        expect => 'hello world',
    );
}

sub test_advanced_filters : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
<%class>
method Cache ($key, $set_options) {
    Mason::AdvancedFilter->new(filter => sub {
        $self->comp_cache->compute($key, $_[0], $set_options);
    });
}
method Repeat ($times) {
    Mason::AdvancedFilter->new(filter => sub {
        my $content = '';
        foreach my $i (1..$times) {
            $content .= $_[0]->();
        }
        return $content;
    });
}
</%class>

% my $i = 1;
<% $.Repeat(3) { %>
i = <% $i++ %>
<% } %>
EOF
        expect => <<'EOF',
i = 1
i = 2
i = 3
EOF
    );
}

sub test_missing_close_brace : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
<% $.Upper { %>
Hello world
EOF
        expect_error => qr/<% { %> without matching <% } %>/
    );
}

sub test_bad_filter_expression : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
<% 'foobar' { %>
Hello world
<% } %>
EOF
        expect_error => qr/'foobar' is neither a code ref/
    );
}

1;
