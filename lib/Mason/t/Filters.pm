package Mason::t::Filters;
use Test::Warn;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_basic : Tests {
    my $self = shift;
    $self->test_comp(
        src => '
% sub { ucfirst(shift) } {{
<% "hello world?" %>
% }}
',
        expect => '
Hello world?
',
    );
}

sub test_filters : Tests {
    my $self = shift;
    $self->test_comp(
        src => '
<%class>
method Upper () { sub { uc(shift) } }
</%class>

% $.Upper {{   # start Upper
Hello World.
% }}           # end Upper

% sub { ucfirst(shift) } {{   
<% "hello world?" %>
% }}   

% sub { tr/A-Z/a-z/; $_ } {{
Hello World!
% }}
',
        expect => '
HELLO WORLD.
Hello world?
hello world!
',
    );
}

sub test_filter_pipe : Tests {
    my $self = shift;
    $self->test_comp(
        src => '
<%class>
method Upper () { sub { uc(shift) } }
method Lower () { sub { lc(shift) } }
method UpFirst () { sub { ucfirst(shift) } }
</%class>

<% "HELLO" | Lower %>
<% "hello" | UpFirst %>
<% "HELLO" | UpFirst,Lower %>
<% "hello" | Lower,   UpFirst %>
<% "HeLlO" | Lower, Upper %>
<% "HeLlO" | Upper, Lower %>
',
        expect => '
hello
Hello
Hello
hello
hello
HELLO
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
% $.MyRepeat(3) {{
count = <% ++$count %>
% }}

<%perl>
my $content = $m->filter($.MyRepeat(2), sub { "count == " . ++$count . "\n" });
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
% sub { lc(shift) } {{
<% $msg %>
% }}
EOF
        expect => 'hello world',
    );
}

sub test_repeat : Tests {
    my $self = shift;
    $self->test_comp(
        src => <<'EOF',
% my $i = 1;
% $.Repeat(3) {{
i = <% $i++ %>
% }}
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
% sub { ucfirst(shift) } {{
%   sub { tr/e/a/; $_ } {{
%     sub { lc(shift) } {{
HELLO
%     }}
%   }}
% }}
goodbye

% sub { ucfirst(shift) }, sub { tr/e/a/; $_ }, sub { lc(shift) } {{
HELLO
% }}
goodbye
EOF
        expect => <<'EOF',
Hallo
goodbye

Hallo
goodbye
EOF
    );
}

sub test_misc_standard_filters : Tests {
    my $self = shift;

    $self->test_comp(
        src    => 'the <% $m->filter($.Trim, "   quick brown   ") %> fox',
        expect => 'the quick brown fox'
    );
    $self->test_comp(
        src => '
% $.Capture(\my $buf) {{
2 + 2 = <% 2+2 %>
% }}
<% reverse($buf) %>

% $.Tee(\my $buf2) {{
3 + 3 = <% 3+3 %>
% }}
<% reverse($buf2) %>

---
% $.NoBlankLines {{

one




two

% }}
---
',
        expect => '
4 = 2 + 2

3 + 3 = 6

6 = 3 + 3

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
<%class>
has "items";
has "yield";
</%class>

% foreach my $item (@{$.items}) {
<% $.yield->($item) %>
% }
',
    );
    $self->test_comp(
        src => '
% $.CompCall ("list_items.mi", items => [1,2,3]) {{
<li><% $_[0] %></li>
% }}
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
% sub { uc($_[0]) } {{
%   $self->$orig();
% }}
</%around>

EOF
        expect => <<'EOF',
HELLO
EOF
    );
}

# Test old filter syntax, still currently supported
#
sub test_old_syntax : Tests {
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
<% } %>

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

sub test_filter_comment : Tests {
    my $self = shift;
    $self->test_comp(
        src => '
<%class>
method LESSp () { sub { uc(shift) } }
</%class>
% $.LESSp {{
#header {
    text-align: left;
}
% }}
#footer {
    text-align: right;
}
',
        expect => '
#HEADER {
    TEXT-ALIGN: LEFT;
}
#footer {
    text-align: right;
}
',
    );
}

sub test_no_undef_warning : Tests {
    my $self = shift;
    warnings_are {
        $self->test_comp(
            src => '
<%class>
method Upper () { sub { uc(shift) } }
method Upper2 () {
    return Mason::DynamicFilter->new(
        filter => sub {
            my $yield = $_[0];
            return uc($yield->());
        }
    );
}
</%class>

<%filter Upper3>
<% uc($yield->()) %>
</%filter>

a = <% "a" | Upper %>.
undef = <% undef | Upper %>.

a = <% "a" | Upper2 %>.
undef = <% undef | Upper2 %>.

a = <% "a" | Upper3 %>.
undef = <% undef | Upper3 %>.
',
            expect => '
a = A.
undef = .

a = A.
undef = .

a = A.
undef = .
',
        );
    }
    [], "no warnings on undef";
}

1;
