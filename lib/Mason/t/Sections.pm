package Mason::t::Sections;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub test_sections : Test(1) {
    shift->test_comp(
        component => <<'EOF',
<%init>
my $message2 = "Goodbye...";
</%init>
<%class>
my $message = "Hello World!";
</%class>
<BODY>
<% $message %>
% $self->foo();
<% $message2 %>
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

1;
