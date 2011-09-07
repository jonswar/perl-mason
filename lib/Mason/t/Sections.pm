package Mason::t::Sections;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_sections : Tests {
    my $self = shift;
    $self->test_comp(
        src => <<'EOF',
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

<%method method_call>
<% $message %>

<%init>
my $message = "method call";
</%init>
</%method>

<%before method_call>
before method call
</%before>

<%after method_call>
after method call
</%after>

<%override render>
start override
<% super() %>
end override
</%override>

<%method method_call_with_arglist ($foo, $bar)>
<% $foo %> - <% $bar %>
</%method>

EOF
        expect => <<'EOF',
start override
<BODY>
class message

before method call

method call

after method call

3 - 4
init message
</BODY>

end override
EOF
    );
}

sub test_perl_section_newlines : Tests {
    my $self = shift;
    $self->test_comp(
        src => <<'EOF',
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

sub test_text_section : Tests {
    my $self = shift;
    $self->test_comp(
        src => <<'EOF',
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

sub test_empty_sections : Tests {
    my $self = shift;
    $self->test_comp(
        src => '
hi
<%after foo></%after>
<%around foo></%around>
<%before foo></%before>
<%method foo></%method>
<%filter bar></%filter>
<%override allow_path_info></%override>
<%class></%class>
<%doc></%doc>
<%flags></%flags>
<%init></%init>
<%perl></%perl>
<%text></%text>
bye
',
        expect => "hibye",
    );
}

1;
