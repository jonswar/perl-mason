package Mason::t::TopLevelResolve;
use strict;
use warnings;
use Test::Most;
use base qw(Mason::Test::Class);

sub test_resolve : Tests(13) {
    my $self = shift;

    my $try = sub {
        my ( $run_path, $existing_paths, $resolve_path, $path_info ) = @_;
        $path_info ||= '';

        $self->setup_dirs;
        foreach my $existing_path (@$existing_paths) {
            $self->add_comp(
                path      => $existing_path,
                component => 'path: <% $self->comp_path %>; path_info: <% $m->path_info %>'
            );
        }
        my $desc = sprintf( "run %s against %s", $run_path, join( ",", @$existing_paths ) );
        if ( defined($resolve_path) ) {
            is( $self->{interp}->srun($run_path),
                "path: $resolve_path; path_info: $path_info", $desc );
        }
        else {
            throws_ok { $self->{interp}->srun($run_path) } qr/could not find component/, $desc;
        }
    };

    my $run_path = '/foo/bar/baz';
    $try->( $run_path, ['/foo/bar/baz.m'],           '/foo/bar/baz.m',           '' );
    $try->( $run_path, ['/foo/bar/baz/dhandler.pm'], '/foo/bar/baz/dhandler.pm', '' );
    $try->( $run_path, ['/foo/bar.m'],               '/foo/bar.m',               'baz' );
    $try->( $run_path, ['/foo/bar/dhandler.pm'],     '/foo/bar/dhandler.pm',     'baz' );
    $try->( $run_path, ['/foo.m'],                   '/foo.m',                   'bar/baz' );
    $try->( $run_path, ['/foo/dhandler.pm'],         '/foo/dhandler.pm',         'bar/baz' );
    $try->( $run_path, ['/dhandler.pm'],             '/dhandler.pm',             'foo/bar/baz' );
    $try->( $run_path, [ '/dhandler.pm',     '/foo/dhandler.pm' ], '/foo/dhandler.pm', 'bar/baz' );
    $try->( $run_path, [ '/foo/dhandler.pm', '/foo/bar.m' ],       '/foo/bar.m',       'baz' );

    # Not found
    $try->( $run_path, ['/foo/bar/baz/blarg.m'],           undef );
    $try->( $run_path, ['/foo/bar/baz/blarg/dhandler.pm'], undef );
    $try->( $run_path, ['/foo/blarg.m'],                   undef );
    $try->( $run_path, ['/foo/blarg/dhandler.pm'],         undef );
}

1;
