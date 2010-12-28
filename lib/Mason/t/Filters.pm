package Mason::t::Filters;
use strict;
use warnings;
use base qw(Mason::Test::Class);
use Test::More;

sub test_filters : Test(1) {
    my $self = shift;
    $self->test_comp(
        src => '
<%class>
method Upper () { sub { uc(shift) } }
</%class>

<% $.Upper { %>
Hello World.
</%>

<% sub { ucfirst(shift) } { %>
<% "hello world?" %>
</%>

<% sub { lc(shift) } { %>
Hello World!
</%>
',
        expect => '
HELLO WORLD.
Hello world?
hello world!
',
    );
}

sub test_lexical : Test(1) {
    my $self = shift;
    $self->test_comp(
        src => <<'EOF',
% my $msg = "Hello World";
<% sub { lc(shift) } { %>
<% $msg %>
</%>
EOF
        expect => 'hello world',
    );
}

sub test_repeat : Test(1) {
    my $self = shift;
    $self->test_comp(
        src => <<'EOF',
% my $i = 1;
<% $.Repeat(3) { %>
i = <% $i++ %>
</%>
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
        src => <<'EOF',
<% sub { ucfirst(shift) } { %>
<% sub { lc(shift) } { %>
<% sub { Mason::Util::trim(shift) } { %>
   HELLO
</%>
</%>
</%>
goodbye

<% sub { ucfirst(shift) }, sub { lc(shift) }, sub { Mason::Util::trim(shift) } { %>
   HELLO
</%>
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
        src => <<'EOF',
% my $i = 1;
% foreach my $key (qw(foo bar)) {
<% $.Repeat(3), $.Cache($key) { %>
i = <% $i++ %>
</%>
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
        src => <<'EOF',
% my $i = 1;
% foreach my $key (qw(foo foo)) {
<% $.Cache($key), $.Repeat(3) { %>
i = <% $i++ %>
</%>
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

sub test_misc_standard_filters : Test(2) {
    my $self = shift;

    $self->test_comp(
        src    => 'the <% $.Trim { %>    quick brown     </%> fox',
        expect => 'the quick brown fox'
    );
    $self->test_comp(
        src => <<'EOF',
<% $.Capture(\my $buf) { %>
2 + 2 = <% 2+2 %>
</%>
<% reverse($buf) %>

---
<% $.NoBlankLines { %>

one




two

</%>
---
EOF
        expect => <<'EOF',
4 = 2 + 2

---
one
two
---

EOF
    );
}

sub test_around : Test(1) {
    my $self = shift;
    $self->test_comp(
        src => <<'EOF',
hello

<%around main>
<% sub { uc($_[0]) } { %>
% $self->$orig();
</%>
</%around>        

EOF
        expect => <<'EOF',
HELLO
EOF
    );
}

1;
