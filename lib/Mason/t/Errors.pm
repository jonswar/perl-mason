package Mason::t::Errors;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_comp_errors : Tests {
    my $self = shift;
    my $try  = sub {
        my ( $src, $expect_error, %extra ) = @_;
        $self->test_comp(
            src          => $src,
            expect_error => $expect_error,
            desc         => $expect_error,
            %extra
        );
    };
    my $root = $self->interp->comp_root->[0];

    $try->(
        '<& /does/not/exist &>',
        qr/could not find component for path '\/does\/not\/exist' - component root is \Q[$root]\E/,
    );
    $try->( '<%method>',                   qr/<%method> block requires a name/ );
    $try->( '<%before>',                   qr/<%before> block requires a name/ );
    $try->( '<%init>',                     qr/<%init> without matching <\/%init>/ );
    $try->( '<%attr>',                     qr/unknown block '<%attr>'/ );
    $try->( '<%blah>',                     qr/unknown block '<%blah>'/ );
    $try->( '<%init foo>',                 qr/<%init> block does not take a name/ );
    $try->( '<%',                          qr/'<%' without matching '%>'/ );
    $try->( 'foo %>',                      qr/'%>' without matching '<%'/ );
    $try->( '<& foo',                      qr/'<&' without matching '&>'/ );
    $try->( 'foo &>',                      qr/'&>' without matching '<&'/ );
    $try->( '%my $i = 1;',                 qr/% must be followed by whitespace/ );
    $try->( "<%5\n\n%>",                   qr/whitespace required after '<%' at .* line 1/ );
    $try->( "<%\n\n5%>",                   qr/whitespace required before '%>' at .* line 3/ );
    $try->( "% \$.Upper {{\nHi",           qr/'{{' without matching '}}'/ );
    $try->( "Hi\n% }}",                    qr/'}}' without matching '{{'/ );
    $try->( '<%method 1a>Hi</%method>',    qr/Invalid method name '1a'/ );
    $try->( '<%method cmeta>Hi</%method>', qr/'cmeta' is reserved.*method name/ );
    $try->(
        "<%method a>Hi</%method>\n<%method a>Bye</%method>",
        qr/Duplicate definition of method 'a'/
    );
    $try->( "<%before 1a>Hi</%before>", qr/Invalid method modifier name '1a'/ );
    $try->(
        "<%before a>Hi</%before>\n<%before a>Bye</%before>",
        qr/Duplicate definition of method modifier 'before a'/
    );
    $try->(
        '<%method b><%after main>Hi</%after></%method>',
        qr/Cannot nest <%after> block inside <%method> block/
    );
    $try->( "% 'foobar' {{\nHi\n% }}\n",     qr/'foobar' is neither a code ref/ );
    $try->( "<%flags>\nfoo => 1\n</%flags>", qr/Invalid flag 'foo'/ );
    $try->( "<%flags>\nextends => 'blah'\n</%flags>",
        qr/could not load '\/blah' for extends flag/ );
    $try->( "<%flags>\nextends => %foo\n</%flags>", qr/Global symbol/ );
    $try->( '<% $foo %>', qr/Global symbol "\$foo" requires explicit package name/ );
    $try->( 'die "blargh";', qr/blargh/, path => '/blargh.mp' );

    # Error line numbers
    #
    $try->( "%\nb\n% die;",                               qr/Died at .* line 3/ );
    $try->( "<%method foo>\n1\n2\n3\n</%method>\n% die;", qr/Died at .* line 6/ );
}

sub test_bad_allow_globals : Tests {
    my $self = shift;
    throws_ok { $self->create_interp( allow_globals => ['@p'] ) } qr/only scalar globals supported/;
    throws_ok { $self->create_interp( allow_globals => ['i-'] ) } qr/not a valid/;
}

sub test_non_comp_errors : Tests {
    my $self = shift;
    throws_ok { $self->interp->_make_request()->current_comp_class }
    qr/cannot determine current_comp_class/;
    throws_ok { Mason->new() } qr/Attribute \(comp_root\) is required/;
}

1;
