package Mason::t::ResolveURI;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_resolve : Tests(32) {
    my $self = shift;

    my @interp_params = ();
    my $try           = sub {
        my ( $run_path, $existing_paths, $resolve_path, $path_info ) = @_;
        $path_info ||= '';

        $self->setup_dirs(@interp_params);
        foreach my $existing_path (@$existing_paths) {
            my $allow_path_info = 0;
            if ( $existing_path =~ /=1$/ ) {
                substr( $existing_path, -2, 2 ) = '';
                $allow_path_info = 1;
            }
            $self->add_comp(
                path => $existing_path,
                src  => join( "",
                    ( $allow_path_info ? "%% method allow_path_info { 1 }\n" : "" ),
                    "path: <% \$self->cmeta->path %>; path_info: <% \$m->path_info %>" )
            );
        }
        my $desc = sprintf( "run %s against %s", $run_path, join( ",", @$existing_paths ) );
        if ( defined($resolve_path) ) {
            is( $self->interp->run($run_path)->output,
                "path: $resolve_path; path_info: $path_info", $desc );
        }
        else {
            throws_ok { $self->interp->run($run_path)->output }
            qr/could not find component for request path/,
              $desc;
        }
    };

    my $run_path = '/foo/bar/baz';

    $try->( $run_path, ['/foo/bar/baz.m'],          '/foo/bar/baz.m',          '' );
    $try->( $run_path, ['/foo/bar/baz/dhandler.m'], '/foo/bar/baz/dhandler.m', '' );
    $try->( $run_path, ['/foo/bar/baz/index.m'],    '/foo/bar/baz/index.m',    '' );
    $try->( $run_path, ['/foo/bar.m=1'],            '/foo/bar.m',              'baz' );
    $try->( $run_path, ['/foo/bar/dhandler.m'],     '/foo/bar/dhandler.m',     'baz' );
    $try->( $run_path, ['/foo.m=1'],                '/foo.m',                  'bar/baz' );
    $try->( $run_path, ['/foo/dhandler.m'],         '/foo/dhandler.m',         'bar/baz' );
    $try->( $run_path, ['/dhandler.m'],             '/dhandler.m',             'foo/bar/baz' );
    $try->( $run_path, [ '/dhandler.m',     '/foo/dhandler.m' ], '/foo/dhandler.m', 'bar/baz' );
    $try->( $run_path, [ '/foo/dhandler.m', '/foo/bar.m=1' ],    '/foo/bar.m',      'baz' );
    $try->( $run_path, [ '/foo/dhandler.m', '/foo/bar.m' ],      '/foo/dhandler.m', 'bar/baz' );

    # Not found
    $try->( $run_path, ['/foo/bar.m'],                    undef );
    $try->( $run_path, ['/foo.m'],                        undef );
    $try->( $run_path, ['/foo/bar/baz/blarg.m'],          undef );
    $try->( $run_path, ['/foo/bar/baz/blarg/dhandler.m'], undef );
    $try->( $run_path, ['/foo/bar/baz'],                  undef );
    $try->( $run_path, ['/foo/dhandler'],                 undef );
    $try->( $run_path, ['/foo/bar/index.m'],              undef );
    $try->( $run_path, ['/foo/blarg.m'],                  undef );
    $try->( $run_path, ['/foo/blarg/dhandler.m'],         undef );

    # Can't access autobase, dhandler or index directly.
    $try->( '/foo/Base',     ['/foo/Base.m'],     undef );
    $try->( '/foo/dhandler', ['/foo/dhandler.m'], '/foo/dhandler.m', 'dhandler' );
    $try->( '/foo/index',    ['/foo/index.m'],    undef );

    # no autoextend_run_path
    @interp_params = ( autoextend_request_path => [], top_level_extensions => ['.html'] );
    $try->( '/foo/bar/baz.html', ['/foo/bar/baz.html'], '/foo/bar/baz.html', '' );
    $try->( '/foo/bar/baz.html', ['/foo/bar/baz.html.m'], undef );

    # dhandler_names
    @interp_params = ( dhandler_names => ['dhandler'] );
    $try->( $run_path, ['/foo/bar/baz/dhandler.m'], undef );
    $try->( $run_path, ['/foo/bar/baz/dhandler'],   '/foo/bar/baz/dhandler', '' );
    $try->( $run_path, ['/foo/bar/dhandler'],       '/foo/bar/dhandler', 'baz' );

    # index_names
    @interp_params = ( index_names => [ 'index', 'index2' ] );
    $try->( $run_path, ['/foo/bar/baz/index.m'], undef );
    $try->( $run_path, ['/foo/bar/baz/index'],   '/foo/bar/baz/index', '' );
    $try->( $run_path, ['/foo/bar/baz/index2'],  '/foo/bar/baz/index2', '' );
    $try->( $run_path, [ '/foo/bar/baz/index2', '/foo/bar/baz/index' ], '/foo/bar/baz/index', '' );
}

sub test_decline : Tests(7) {
    my $self = shift;

    my @existing_paths =
      qw(/foo/bar.m /foo/bar/dhandler.m /foo/bar/index.m /foo.m /foo/dhandler.m /dhandler.m);
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
            $self->add_comp( path => '/Base.pm', src => 'method allow_path_info { 1 }' );
        }
        my $desc = sprintf( "declining: %s", join( ",", @paths_to_decline ) || '<nothing>' );
        if ( defined($resolve_path) ) {
            is( $self->interp->run($run_path)->output,
                "path: $resolve_path; path_info: $path_info", $desc );
        }
        else {
            throws_ok { $self->interp->run($run_path)->output }
            qr/could not find component for request path/,
              $desc;
        }
        push( @paths_to_decline, $resolve_path );
    };

    # Repeatedly try /foo/bar, test the expected page component, then add
    # that component to the decline list and try again.
    #
    $try->( '/foo/bar.m',          '' );
    $try->( '/foo/bar/index.m',    '' );
    $try->( '/foo/bar/dhandler.m', '' );
    $try->( '/foo.m',              'bar' );
    $try->( '/foo/dhandler.m',     'bar' );
    $try->( '/dhandler.m',         'foo/bar' );
    $try->(undef);
}

1;
