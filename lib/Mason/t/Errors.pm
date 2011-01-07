package Mason::t::Errors;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_errors : Test(20) {
    my $self = shift;
    my $try  = sub {
        my ( $src, $expect_error ) = @_;
        $self->test_comp( src => $src, expect_error => $expect_error );
    };
    my $root = $self->interp->comp_root->[0];

    $try->(
        '<& /does/not/exist &>',
        qr/could not find component for path '\/does\/not\/exist' - component root is \Q[$root]\E/,
    );
    $try->( '<%method>',                  qr/<%method> block requires a name/ );
    $try->( '<%before>',                  qr/<%before> block requires a name/ );
    $try->( '<%init>',                    qr/<%init> without matching <\/%init>/ );
    $try->( '<%',                         qr/'<%' without matching '%>'/ );
    $try->( '<& foo',                     qr/'<&' without matching '&>'/ );
    $try->( '%my $i = 1;',                qr/% must be followed by whitespace/ );
    $try->( '%%my $i = 1;',               qr/%% must be followed by whitespace/ );
    $try->( "<%attr>\n123\n</%attr>",     qr/Invalid attribute line '123'/ );
    $try->( "<%attr>\n\$\$abc\n</%attr>", qr/Invalid attribute line '\$\$abc'/ );
    $try->( '<% $.Upper { %>Hi',          qr/<% { %> without matching <\/%>/ );
    $try->( '<%method 1a>Hi</%method>',   qr/Invalid method name '1a'/ );
    $try->(
        "<%method a>Hi</%method>\n<%method a>Bye</%method>",
        qr/Duplicate definition of method 'a'/
    );
    $try->( "<%before 1a>Hi</%before>", qr/Invalid method modifier name '1a'/ );
    $try->(
        "<%before a>Hi</%before>\n<%before a>Bye</%before>",
        qr/Duplicate definition of method modifier 'before a'/
    );
    $try->( "<%wrap>a</%wrap><%wrap>b</%wrap>", qr/Multiple wrap blocks/ );
    $try->( "<%wrap hi>a</%wrap>",              qr/<%wrap> block does not take a name/ );
    $try->( '<% "foobar" { %>Hi</%>',           qr/'foobar' is neither a code ref/ );
    $try->( "<%flags>\nfoo => 1\n</%flags>",    qr/Invalid flag 'foo'/ );
    $try->( '<% $foo %>', qr/Global symbol "\$foo" requires explicit package name/ );
}

1;
