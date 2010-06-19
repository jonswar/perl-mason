package Mason::t::Sections;
use strict;
use warnings;
use base qw(Mason::Test::Class);

sub test_class : Test(1) {
    shift->test_comp(
        component => <<'EOF',
<%class>
my $message = "Hello World!";
</%class>
<BODY>
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

1;
