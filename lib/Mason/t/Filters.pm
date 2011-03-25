package Mason::t::Filters;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_filters : Tests {
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

sub test_filter_block : Tests {
    my $self = shift;
    $self->test_comp(
        src => '
<%filter MyRepeat ($count)>
% for (my $i=0; $i<$count; $i++) {
* <% $yield->() %>\
% }
</%filter>

% my $count = 0;
<% $.MyRepeat(3) { %>
count = <% ++$count %>
</%>

<%perl>
my $content = $m->apply_filter($.MyRepeat(2), sub { "count == " . ++$count . "\n" });
print(uc($content));
</%perl>
',
        expect => '
* count = 1
* count = 2
* count = 3
* COUNT == 4
* COUNT == 5
',
    );
}

sub test_lexical : Tests {
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

sub test_repeat : Tests {
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

sub test_nested : Tests {
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

sub test_misc_standard_filters : Tests {
    my $self = shift;

    $self->test_comp(
        src    => 'the <% $.Trim { %>    quick brown     </%> fox',
        expect => 'the quick brown fox'
    );
    $self->test_comp(
        src => '
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
',
        expect => '
4 = 2 + 2

---
one
two
---

',
    );
}

sub test_compcall_filter : Tests {
    my $self = shift;

    $self->add_comp(
        path => '/list_items.mi',
        src  => '
<%args>
$.items
$.yield
</%args>

% foreach my $item (@{$.items}) {
<% $.yield->($item) %>
% }
',
    );
    $self->test_comp(
        src => '
<% $.CompCall ("list_items.mi", items => [1,2,3]) { %>
<li><% $_[0] %></li>
<% } %>
',
        expect => '
<li>1</li>

<li>2</li>

<li>3</li>
',
    );
}

sub test_around : Tests {
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
