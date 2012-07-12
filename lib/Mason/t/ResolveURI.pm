package Mason::t::ResolveURI;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_resolve : Tests {
    my $self = shift;

    my @interp_params = ();
    my $try           = sub {
        my ( $run_path, $existing_paths, $resolve_path, $path_info ) = @_;
        $path_info ||= '';

        $self->setup_dirs(@interp_params);
        foreach (@$existing_paths) {
            my $existing_path = $_;
            my $allow_path_info = 0;
            if ( $existing_path =~ /=1$/ ) {
                substr( $existing_path, -2, 2 ) = '';
                $allow_path_info = 1;
            }
            $self->add_comp(
                path => $existing_path,
                src  => join( "",
                    ( $allow_path_info ? "<%class>method allow_path_info { 1 }</%class>\n" : "" ),
                    "path: <% \$self->cmeta->path %>; path_info: <% \$m->path_info %>" )
            );
        }
        my $desc = sprintf( "run %s against %s", $run_path, join( ",", @$existing_paths ) );
        if ( defined($resolve_path) ) {
            my $good = "path: $resolve_path; path_info: $path_info";
            is( $self->interp->run($run_path)->output,
                $good, "$desc = matched $good" );
        }
        else {
            throws_ok { $self->interp->run($run_path)->output }
            qr/could not resolve request path/,
              "$desc = failed to match";
        }
    };

    my $run_path = '/foo/bar/baz';

    $try->( $run_path, ['/foo/bar/baz.mc'],          '/foo/bar/baz.mc',          '' );
    $try->( $run_path, ['/foo/bar/baz/dhandler.mc'], '/foo/bar/baz/dhandler.mc', '' );
    $try->( $run_path, ['/foo/bar/baz/index.mc'],    '/foo/bar/baz/index.mc',    '' );
    $try->( $run_path, ['/foo/bar.mc=1'],            '/foo/bar.mc',              'baz' );
    $try->( $run_path, ['/foo/bar/dhandler.mc'],     '/foo/bar/dhandler.mc',     'baz' );
    $try->( $run_path, ['/foo.mc=1'],                '/foo.mc',                  'bar/baz' );
    $try->( $run_path, ['/foo/dhandler.mc'],         '/foo/dhandler.mc',         'bar/baz' );
    $try->( $run_path, ['/dhandler.mc'],             '/dhandler.mc',             'foo/bar/baz' );
    $try->( $run_path, [ '/dhandler.mc',     '/foo/dhandler.mc' ], '/foo/dhandler.mc', 'bar/baz' );
    $try->( $run_path, [ '/foo/dhandler.mc', '/foo/bar.mc=1' ],    '/foo/bar.mc',      'baz' );
    $try->( $run_path, [ '/foo/dhandler.mc', '/foo/bar.mc' ],      '/foo/dhandler.mc', 'bar/baz' );

    # Not found
    $try->( $run_path, ['/foo/bar.mc'],                    undef );
    $try->( $run_path, ['/foo.mc'],                        undef );
    $try->( $run_path, ['/foo/bar/baz/blarg.mc'],          undef );
    $try->( $run_path, ['/foo/bar/baz/blarg/dhandler.mc'], undef );
    $try->( $run_path, ['/foo/bar/baz'],                   undef );
    $try->( $run_path, ['/foo/dhandler'],                  undef );
    $try->( $run_path, ['/foo/bar/index.mc'],              undef );
    $try->( $run_path, ['/foo/blarg.mc'],                  undef );
    $try->( $run_path, ['/foo/blarg/dhandler.mc'],         undef );

    # Can't access autobase or dhandler directly, but can access index
    $try->( '/foo/Base',     ['/foo/Base.mc'],     undef );
    $try->( '/foo/dhandler', ['/foo/dhandler.mc'], '/foo/dhandler.mc', 'dhandler' );
    $try->( '/foo/index',    ['/foo/index.mc'],    '/foo/index.mc' );

    # no autoextend_run_path
    @interp_params = ( autoextend_request_path => 0, top_level_extensions => ['.html'] );
    $try->( '/foo/bar/baz.html', ['/foo/bar/baz.html'], '/foo/bar/baz.html', '' );
    $try->( '/foo/bar/baz.html', ['/foo/bar/baz.html.mc'], undef );
    $try->( "/foo.mc/bar.mi",    ['/foo.mc/bar.mi'],       undef );
    @interp_params = ( autoextend_request_path => 0, top_level_extensions => [] );
    $try->( '/foo/bar/baz.html', ['/foo/bar/baz.html'], '/foo/bar/baz.html', '' );
    $try->( "/foo.mc/bar.mi",    ['/foo.mc/bar.mi'],    '/foo.mc/bar.mi',    '' );

    # dhandler_names
    @interp_params = ( dhandler_names => ['dhandler'] );
    $try->( $run_path, ['/foo/bar/baz/dhandler.mc'], undef );
    $try->( $run_path, ['/foo/bar/baz/dhandler'],    '/foo/bar/baz/dhandler', '' );
    $try->( $run_path, ['/foo/bar/dhandler'],        '/foo/bar/dhandler', 'baz' );

    # index_names
    @interp_params = ( index_names => [ 'index', 'index2' ] );
    $try->( $run_path, ['/foo/bar/baz/index.mc'], undef );
    $try->( $run_path, ['/foo/bar/baz/index'],    '/foo/bar/baz/index', '' );
    $try->( $run_path, ['/foo/bar/baz/index2'],   '/foo/bar/baz/index2', '' );
    $try->( $run_path, [ '/foo/bar/baz/index2', '/foo/bar/baz/index' ], '/foo/bar/baz/index', '' );

    # trailing slashes
    $try->( '/foo',      ['/foo.mc=1'], '/foo.mc', '' );
    $try->( '/foo/',     ['/foo.mc=1'], '/foo.mc', '/' );
    $try->( '/foo/bar',  ['/foo.mc=1'], '/foo.mc', 'bar' );
    $try->( '/foo/bar/', ['/foo.mc=1'], '/foo.mc', 'bar/' );
    $try->( '/foo/',     ['/foo.mc'],   undef );
    @interp_params = ( dhandler_names => ['dhandler'] );
    $try->( '/foo/',     ['/foo/dhandler'], '/foo/dhandler', '/' );
    $try->( '/foo/bar',  ['/foo/dhandler'], '/foo/dhandler', 'bar' );
    $try->( '/foo/bar/', ['/foo/dhandler'], '/foo/dhandler', 'bar/' );
    @interp_params = ( index_names => ['index'] );
    $try->( '/foo/', ['/foo/index'], undef );
    $try->( '/foo/', ['/foo/index=1'], '/foo/index', '/' );
    @interp_params = ( dhandler_names => ['dhandler'], index_names => ['index'] );
    $try->( '/foo/', ['/foo/dhandler', '/foo/index'], '/foo/dhandler', '/' );
    $try->( '/foo/', ['/foo/dhandler', '/foo/index=1'], '/foo/index', '/' );
}

sub test_decline : Tests {
    my $self = shift;

    my @existing_paths =
      qw(/foo/bar.mc /foo/bar/dhandler.mc /foo/bar/index.mc /foo.mc /foo/dhandler.mc /dhandler.mc);
    my @paths_to_decline = ();
    my $run_path         = '/foo/bar';

    my $try = sub {
        my ( $resolve_path, $path_info ) = @_;
        my %paths_to_decline_hash = map { ( $_, 1 ) } @paths_to_decline;

        $self->setup_dirs();
        foreach my $existing_path (@existing_paths) {
            my $component =
              $paths_to_decline_hash{$existing_path}
              ? '<%perl>$m->decline();</%perl>'
              : 'path: <% $self->cmeta->path %>; path_info: <% $m->path_info %>';
            $self->add_comp(
                path => $existing_path,
                src  => $component,
            );
            $self->add_comp( path => '/Base.mp', src => 'method allow_path_info { 1 }' );
        }
        my $desc = sprintf( "declining: %s", join( ",", @paths_to_decline ) || '<nothing>' );
        if ( defined($resolve_path) ) {
            is( $self->interp->run($run_path)->output,
                "path: $resolve_path; path_info: $path_info", $desc );
        }
        else {
            throws_ok { $self->interp->run($run_path)->output }
            qr/could not resolve request path/,
              $desc;
        }
        push( @paths_to_decline, $resolve_path );
    };

    # Repeatedly try /foo/bar, test the expected page component, then add
    # that component to the decline list and try again.
    #
    $try->( '/foo/bar.mc',          '' );
    $try->( '/foo/bar/index.mc',    '' );
    $try->( '/foo/bar/dhandler.mc', '' );
    $try->( '/foo.mc',              'bar' );
    $try->( '/foo/dhandler.mc',     'bar' );
    $try->( '/dhandler.mc',         'foo/bar' );
    $try->(undef);
}

1;
