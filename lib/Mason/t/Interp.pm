## Please see file perltidy.ERR
## Please see file perltidy.ERR
package Mason::t::Interp;
use Test::Class::Most parent => 'Mason::Test::Class';
use Capture::Tiny qw(capture);

{ package MyInterp; use Moose; extends 'Mason::Interp' }

sub test_base_interp_class : Test(1) {
    my $self = shift;
    my $interp = $self->create_interp( base_interp_class => 'MyInterp' );
    is( ref($interp), 'MyInterp' );
}

sub test_find_paths : Test(6) {
    my $self   = shift;
    my $r1     = $self->temp_dir . "/r1";
    my $r2     = $self->temp_dir . "/r2";
    my $interp = $self->create_interp( comp_root => [ $r1, $r2 ] );
    my @files =
      ( "$r1/foo.m", "$r1/foo/bar.m", "$r2/foo/baz.m", "$r1/foo/blarg.m", "$r2/foo/blarg.m" );
    foreach my $file (@files) {
        $self->mkpath_and_write_file( $file, " " );
    }
    cmp_set(
        [ $interp->all_paths("/") ],
        [qw(/foo.m /foo/bar.m /foo/baz.m /foo/blarg.m)],
        "all_paths(/)"
    );
    cmp_set(
        [ $interp->all_paths("/foo") ],
        [qw(/foo/bar.m /foo/baz.m /foo/blarg.m)],
        "all_paths(/foo)"
    );
    cmp_set( [ $interp->all_paths("/bar") ], [], "all_paths(/bar)" );

    cmp_set(
        [ $interp->glob_paths("/foo/ba*.m") ],
        [qw(/foo/bar.m /foo/baz.m)],
        "glob_paths(/foo/ba*.m)"
    );
    cmp_set( [ $interp->glob_paths("/foo/bl*.m") ], [qw(/foo/blarg.m)], "glob_paths(/foo/bl*.m)" );
    cmp_set( [ $interp->glob_paths("/foo/d*") ], [], "glob_paths(/foo/d*)" );
}

sub test_component_class_prefix : Test(6) {
    my $self = shift;

    my $check_prefix = sub {
        my $interp = shift;
        my $regex  = "^" . $interp->component_class_prefix . "::";
        like( $interp->load('/foo.m'), qr/$regex/, "prefix at beginning of path" );
    };

    $self->add_comp( path => '/foo.m', src => 'foo' );

    my @interp =
      map { $self->create_interp() } ( 0 .. 1 );
    ok( $interp[0]->component_class_prefix ne $interp[1]->component_class_prefix,
        "different prefixes" );
    ok( $interp[0]->load('/foo.m') ne $interp[1]->load('/foo.m'), "different classnames" );

    $check_prefix->( $interp[0] );
    $check_prefix->( $interp[1] );

    $interp[2] = $self->create_interp( component_class_prefix => 'Blah' );
    is( $interp[2]->component_class_prefix, 'Blah', 'specified prefix' );
    $check_prefix->( $interp[2] );
}

sub test_no_data_dir : Test(1) {
    my $self = shift;
    my $interp = Mason->new( comp_root => $self->comp_root );
    ok( -d $interp->data_dir );
}

sub test_bad_param : Test(1) {
    my $self = shift;
    throws_ok { $self->create_interp( foo => 5 ) } qr/Found unknown attribute/;
}

sub test_comp_exists : Test(3) {
    my $self = shift;

    $self->add_comp( path => '/comp_exists/one.m', src => 'hi' );
    my $interp = $self->interp;
    ok( $interp->comp_exists('/comp_exists/one.m') );
    ok( !$interp->comp_exists('/comp_exists/two.m') );
    throws_ok { $interp->comp_exists('one.m') } qr/not an absolute/;
}

sub test_out_method : Test(15) {
    my $self = shift;

    $self->add_comp( path => '/out_method/hi.m', src => 'hi' );

    my $buffer = '';
    my $try    = sub {
        my ( $out_method, $expect_result, $expect_buffer, $expect_stdout, $desc ) = @_;
        my ( $result, $stdout );
        my @params = ( $out_method ? ( { out_method => $out_method } ) : () );
        ($stdout) = capture {
            $result = $self->interp->run( @params, '/out_method/hi.m' );
        };
        is( $stdout,         $expect_stdout, "stdout - $desc" );
        is( $buffer,         $expect_buffer, "buffer - $desc" );
        is( $result->output, $expect_result, "result->output - $desc" );
    };

    $try->( undef, 'hi', '', '', 'undef' );
    $try->( sub { print $_[0] }, '', '', 'hi', 'sub print' );
    $try->( sub { $buffer .= uc( $_[0] ) }, '', 'HI', '', 'sub buffer .=' );
    $try->( \$buffer, '', 'HIhi', '', '\$buffer' );

    $buffer = '';
    $self->setup_interp( out_method => sub { print scalar( reverse( $_[0] ) ) } );
    $try->( undef, '', '', 'ih', 'print reverse' );
}

1;
