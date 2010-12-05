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

1;
