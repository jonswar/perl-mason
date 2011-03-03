package Mason::t::Syntax;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_replace : Tests {
    shift->test_comp(
        src => <<'EOF',
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

sub test_percent : Tests {
    shift->test_comp(
        src => <<'EOF',
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

sub test_fake_percent : Tests {
    shift->test_comp(
        src => <<'EOF',
some text, a %, and some text
EOF
        expect => <<'EOF',
some text, a %, and some text
EOF
    );
}

sub test_empty_percents : Tests {
    shift->test_comp(
        src => <<'EOF',
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

sub test_empty_percents2 : Tests {
    shift->test_comp(
        src => <<'EOF',
some text,
%
% $m->print('foo, ');
% $m->print(undef);
and some more
EOF
        expect => <<'EOF',
some text,
foo, and some more
EOF
    );
}

sub test_double_percent : Tests {
    shift->test_comp(
        src => <<'EOF',
<%class>
my $i = 5;
</%class>

%% my $j = 0;
%% if ($i == 5) {
%%   $j = $i+1;
%% }
<% $.bar %>

<%method bar>
j = <% $j %>
</%method>

EOF
        expect => <<'EOF',
j = 6
EOF
    );
}

sub test_pure_perl : Tests {
    shift->test_comp(
        path   => '/pureperl.mp',
        src    => 'sub main { print "hello from main" }',
        expect => 'hello from main',
    );
}

sub test_args : Tests {
    my $self = shift;
    $self->add_comp(
        path => '/args.mc',
        src  => '
<%args>
a
b # comment

# comment
 c=>5
d => 6
e => "foo" # comment

f => (isa => "Num", default => 7)
g => (isa => "Num", default => 8) # comment
</%args>

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
        src    => '<& /args.mc, a => 3, b => 4 &>',
        expect => '
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

sub test_multiline_comment : Tests {
    my $self = shift;

    $self->test_comp(
        src => '
hi<%
    # comment

    # another comment

%>bye
',
        expect => 'hibye',
    );
}

sub test_shared : Tests {
    shift->test_parse(
        src => '
<%shared>
$.foo  # a comment
 $.bar => "something"
$.baz => ( isa => "Num", default => 5 )
# another comment
</%shared>
',
        expect => [
            q/has 'foo' => (init_arg => undef/,
            q/has 'bar' => (init_arg => undef, default => "something"/,
            q/has 'baz' => (init_arg => undef,  isa => "Num", default => 5/
        ],
    );
}

sub test_dollar_dot : Tests {
    shift->test_comp(
        src => '
<%args>
foo => 3
</%args>
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

sub test_dollar_m : Tests {
    my $self = shift;
    $self->test_comp(
        src => '
<%class>
method foo  () { $m->print("foo\n") }
</%class>
<%method bar><%perl>$m->print("bar\n");</%perl></%method>
<% $.foo %>
<% $.bar %>
% $m->print("baz\n");
',
        expect => '
foo

bar

baz
',
    );
}

1;
