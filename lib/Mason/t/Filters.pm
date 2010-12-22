package Mason::t::Filters;
use strict;
use warnings;
use base qw(Mason::Test::Class);
use Test::More;
use Method::Signatures::Simple;
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

sub test_repeat : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
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

sub test_nested : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
<% sub { ucfirst(shift) } { %>
<% sub { lc(shift) } { %>
<% sub { Mason::Util::trim(shift) } { %>
   HELLO
<% } %>
<% } %>
<% } %>
goodbye

<% sub { ucfirst(shift) }, sub { lc(shift) }, sub { Mason::Util::trim(shift) } { %>
   HELLO
<% } %>
goodbye
EOF
        expect => <<'EOF',
Hellogoodbye

Hellogoodbye
EOF
    );
}

sub test_cache : Test(2) {
    my $self = shift;

    $self->test_comp(
        component => <<'EOF',
% my $i = 1;
% foreach my $key (qw(foo bar)) {
<% $.Repeat(3), $.Cache($key) { %>
i = <% $i++ %>
<% } %>
% }
EOF
        expect => <<'EOF',
i = 1
i = 1
i = 1
i = 2
i = 2
i = 2
EOF
    );

    $self->test_comp(
        component => <<'EOF',
% my $i = 1;
% foreach my $key (qw(foo foo)) {
<% $.Cache($key), $.Repeat(3) { %>
i = <% $i++ %>
<% } %>
% }
EOF
        expect => <<'EOF',
i = 1
i = 2
i = 3
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
