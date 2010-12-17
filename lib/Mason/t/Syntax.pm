package Mason::t::Syntax;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub test_replace : Test(1) {
    shift->test_comp(
        component => <<'EOF',
<BODY>
<% "Hello World!" %>
</BODY>
EOF
        expect => <<'EOF',
<BODY>
Hello World!
</BODY>
EOF
    );
}

sub test_percent : Test(1) {
    shift->test_comp(
        component => <<'EOF',
<BODY>
% my $message = "Hello World!";
<% $message %>
</BODY>
EOF
        expect => <<'EOF',
<BODY>
Hello World!
</BODY>
EOF
    );
}

sub test_fake_percent : Test(1) {
    shift->test_comp(
        component => <<'EOF',
some text, a %, and some text
EOF
        expect => <<'EOF',
some text, a %, and some text
EOF
    );
}

sub test_empty_percents : Test(1) {
    shift->test_comp(
        component => <<'EOF',
some text,
% 
and some more
EOF
        expect => <<'EOF',
some text,
and some more
EOF
    );
}

sub test_empty_percents2 : Test(1) {
    shift->test_comp(
        component => <<'EOF',
some text,
% 
% $m->print('foo, ');
and some more
EOF
        expect => <<'EOF',
some text,
foo, and some more
EOF
    );
}

sub test_pure_perl : Test(1) {
    shift->test_comp(
        path      => '/pureperl.pm',
        component => 'sub main { print "hello from main" }',
        expect    => 'hello from main',
    );
}

sub test_attr : Test(1) {
    my $self = shift;
    $self->add_comp(
        path      => '/attr.m',
        component => '
<%attr>
a
b # comment

# comment
c=>5
d => 6
e => "foo" # comment

f => (isa => "Num", default => 7)
g => (isa => "Num", default => 8) # comment
</%attr>

a = <% $.a %>
b = <% $.b %>
c = <% $.c %>
d = <% $.d %>
e = <% $.e %>
f = <% $.f %>
g = <% $.g %>
',
    );
    $self->test_comp(
        component => '<& /attr.m, a => 3, b => 4 &>',
        expect    => '
a = 3
b = 4
c = 5
d = 6
e = foo
f = 7
g = 8
'
    );
}

sub test_shared : Test(3) {
    shift->test_parse(
        component => '
<%shared>
$.foo
$.bar => "something"
$.baz => ( isa => "Num", default => 5 )
</%shared>
',
        expect => [
            q/has 'foo' => (init_arg => undef/,
            q/has 'bar' => (init_arg => undef, default => "something"/,
            q/has 'baz' => (init_arg => undef,  isa => "Num", default => 5/
        ],
    );
}

sub test_dollar_dot : Test(1) {
    shift->test_comp(
        component => '
<%attr>
foo => 3
</%attr>
<%shared>
bar => 4
</%shared>

<% $self->show %>

<%method show>
foo = <% $.foo %>
bar = <% $.bar %>
</%method>

<%init>
$self->foo(5);
$self->bar(6);
</%init>
',
        expect => '
foo = 5
bar = 6
'
    );
}

1;
