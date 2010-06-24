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
my $message2 = "Goodbye...";
</%init>

<%class>
my $message = "Hello World!";
</%class>

<BODY>
<% $message %>
% $self->foo();
<%perl>
print "$message2\n";
</%perl>
</BODY>

<%method foo>
<% $message %>
</%method>
EOF
        expect => <<'EOF',
<BODY>
Hello World!

Hello World!
Goodbye...
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

sub test_filter : Test(1) {
    my $self = shift;
    $self->test_comp(
        component => <<'EOF',
Hello world. <% $self->foo %>

<%filter>
$_ = uc($_);
</%filter>

<%method foo>
How are you?

<%filter>
$_ = reverse($_);
</%filter>
</%method>
EOF
        expect => <<'EOF',
HELLO WORLD. 
?UOY ERA WOH

EOF
    );
}

1;
