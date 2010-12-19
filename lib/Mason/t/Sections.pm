package Mason::t::Sections;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub test_sections : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
<%doc>
This should not get printed.
</%doc>

<%init>
my $init_message = $self->init_message();
</%init>

<%class>
my $class_message = "class message";
method init_message  () { "init message" }
</%class>

<BODY>
<% $class_message %>
% $self->method_call();
<% $self->method_call_with_arglist(3, 4) %>
<%perl>
print "$init_message\n";
</%perl>
</BODY>

<%before method_call>
before method call
</%before>

<%after method_call>
after method call
</%after>

<%method method_call>
<% $message %>

<%init>
my $message = "method call";
</%init>
</%method>

<%method method_call_with_arglist ($foo, $bar)>
<% $foo %> - <% $bar %>
</%method>

EOF
        expect => <<'EOF',
<BODY>
class message

before method call

method call

after method call

3 - 4
init message
</BODY>
EOF
    );
}

sub test_perl_section_newlines : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
1<%perl>print "2\n";</%perl>
<%perl>
print "3\n";
</%perl>

4

<%perl>
print "5\n";
</%perl>


6


<%perl>
print "7\n";
</%perl>
EOF
        expect => <<'EOF',
12
3
4
5

6

7
EOF
    );
}

sub test_text_section : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
<%text>
%
<%init>
<%doc>
<% $x %>
</%text>
EOF
        expect => <<'EOF',

%
<%init>
<%doc>
<% $x %>
EOF
    );
}

1;
