package Mason::t::Errors;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_comp_errors : Test(22) {
    my $self = shift;
    my $try  = sub {
        my ( $src, $expect_error ) = @_;
        $self->test_comp( src => $src, expect_error => $expect_error, desc => $expect_error );
    };
    my $root = $self->interp->comp_root->[0];

    $try->(
        '<& /does/not/exist &>',
        qr/could not find component for path '\/does\/not\/exist' - component root is \Q[$root]\E/,
    );
    $try->( '<%method>',                    qr/<%method> block requires a name/ );
    $try->( '<%before>',                    qr/<%before> block requires a name/ );
    $try->( '<%init>',                      qr/<%init> without matching <\/%init>/ );
    $try->( '<%attr>',                      qr/unknown block '<%attr>'/ );
    $try->( '<%',                           qr/'<%' without matching '%>'/ );
    $try->( '<& foo',                       qr/'<&' without matching '&>'/ );
    $try->( '%my $i = 1;',                  qr/% must be followed by whitespace/ );
    $try->( '%%my $i = 1;',                 qr/%% must be followed by whitespace/ );
    $try->( "%% if (1) {\nhi\n%% }",        qr/%%-lines cannot be used to surround content/ );
    $try->( "<%5\n\n%>",                    qr/whitespace required after '<%' at .* line 1/ );
    $try->( "<%\n\n5%>",                    qr/whitespace required before '%>' at .* line 3/ );
    $try->( "<%args>\n\$\$abc\n</%args>",   qr/Invalid attribute line '\$\$abc' at .* line 2/ );
    $try->( "<%args>\na\nb\n123\n</%args>", qr/Invalid attribute line '123' at .* line 4/ );
    $try->( '<% $.Upper { %>Hi',       qr/<% { %> without matching <\/%>/ );
    $try->( '<%method 1a>Hi</%method>',     qr/Invalid method name '1a'/ );
    $try->(
        "<%method a>Hi</%method>\n<%method a>Bye</%method>",
        qr/Duplicate definition of method 'a'/
    );
    $try->( "<%before 1a>Hi</%before>", qr/Invalid method modifier name '1a'/ );
    $try->(
        "<%before a>Hi</%before>\n<%before a>Bye</%before>",
        qr/Duplicate definition of method modifier 'before a'/
    );
    $try->( '<% "foobar" { %>Hi</%>',        qr/'foobar' is neither a code ref/ );
    $try->( "<%flags>\nfoo => 1\n</%flags>", qr/Invalid flag 'foo'/ );
    $try->( '<% $foo %>', qr/Global symbol "\$foo" requires explicit package name/ );
}

sub test_non_comp_errors : Test(1) {
    my $self = shift;
    throws_ok( sub { $self->interp->_make_request()->current_comp_class },
        qr/cannot determine current_comp_class/ );
}

1;
