package Mason::t::Interp;
use Test::Class::Most parent => 'Mason::Test::Class';
use Capture::Tiny qw(capture);

{ package MyInterp; use Moose; extends 'Mason::Interp'; __PACKAGE__->meta->make_immutable() }

sub test_base_interp_class : Tests {
    my $self = shift;
    my $interp = $self->create_interp( base_interp_class => 'MyInterp' );
    is( ref($interp), 'MyInterp' );
}

sub test_find_paths : Tests {
    my $self   = shift;
    my $r1     = $self->temp_dir . "/r1";
    my $r2     = $self->temp_dir . "/r2";
    my $interp = $self->create_interp( comp_root => [ $r1, $r2 ] );
    my @files =
      ( "$r1/foo.mc", "$r1/foo/bar.mc", "$r2/foo/baz.mc", "$r1/foo/blarg.mc", "$r2/foo/blarg.mc" );
    foreach my $file (@files) {
        $self->mkpath_and_write_file( $file, " " );
    }
    cmp_set(
        [ $interp->all_paths("/") ],
        [qw(/foo.mc /foo/bar.mc /foo/baz.mc /foo/blarg.mc)],
        "all_paths(/)"
    );
    cmp_set(
        [ $interp->all_paths() ],
        [qw(/foo.mc /foo/bar.mc /foo/baz.mc /foo/blarg.mc)],
        "all_paths(/)"
    );
    cmp_set(
        [ $interp->all_paths("/foo") ],
        [qw(/foo/bar.mc /foo/baz.mc /foo/blarg.mc)],
        "all_paths(/foo)"
    );
    cmp_set( [ $interp->all_paths("/bar") ], [], "all_paths(/bar)" );

    cmp_set(
        [ $interp->glob_paths("/foo/ba*.mc") ],
        [qw(/foo/bar.mc /foo/baz.mc)],
        "glob_paths(/foo/ba*.mc)"
    );
    cmp_set( [ $interp->glob_paths("/foo/bl*.mc") ],
        [qw(/foo/blarg.mc)], "glob_paths(/foo/bl*.mc)" );
    cmp_set( [ $interp->glob_paths("/foo/d*") ], [], "glob_paths(/foo/d*)" );
}

sub test_component_class_prefix : Tests {
    my $self = shift;

    my $check_prefix = sub {
        my $interp = shift;
        my $regex  = "^" . $interp->component_class_prefix . "::";
        like( $interp->load('/foo.mc'), qr/$regex/, "prefix at beginning of path" );
    };

    $self->add_comp( path => '/foo.mc', src => 'foo' );

    my @interp =
      map { $self->create_interp() } ( 0 .. 1 );
    ok( $interp[0]->component_class_prefix ne $interp[1]->component_class_prefix,
        "different prefixes" );
    ok( $interp[0]->load('/foo.mc') ne $interp[1]->load('/foo.mc'), "different classnames" );

    $check_prefix->( $interp[0] );
    $check_prefix->( $interp[1] );

    $interp[2] = $self->create_interp( component_class_prefix => 'Blah' );
    is( $interp[2]->component_class_prefix, 'Blah', 'specified prefix' );
    $check_prefix->( $interp[2] );
}

sub test_no_data_dir : Tests {
    my $self = shift;
    my $interp = Mason->new( comp_root => $self->comp_root );
    ok( -d $interp->data_dir );
}

sub test_bad_param : Tests {
    my $self = shift;
    throws_ok { $self->create_interp( foo => 5 ) } qr/Found unknown attribute/;
}

sub test_comp_exists : Tests {
    my $self = shift;

    $self->add_comp( path => '/comp_exists/one.mc', src => 'hi' );
    my $interp = $self->interp;
    ok( $interp->comp_exists('/comp_exists/one.mc') );
    ok( !$interp->comp_exists('/comp_exists/two.mc') );
    throws_ok { $interp->comp_exists('one.mc') } qr/not an absolute/;
}

sub test_out_method : Tests {
    my $self = shift;

    $self->add_comp( path => '/out_method/hi.mc', src => 'hi' );

    my $buffer = '';
    my $try    = sub {
        my ( $out_method, $expect_result, $expect_buffer, $expect_stdout, $desc ) = @_;
        my ( $result, $stdout );
        my @params = ( $out_method ? ( { out_method => $out_method } ) : () );
        ($stdout) = capture {
            $result = $self->interp->run( @params, '/out_method/hi' );
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

sub test_no_source_line_numbers : Tests {
    my $self = shift;

    $self->test_parse( src => "hi\n<%init>my \$d = 0</%init>", expect => [qr/\#line/] );
    $self->setup_interp( no_source_line_numbers => 1 );
    $self->test_parse( src => "hi\n<%init>my \$d = 0</%init>", expect => [qr/^(?!(?s:.*)\#line)/] );
}

sub test_class_header : Tests {
    my $self = shift;

    $self->setup_interp( class_header => '# header' );
    $self->test_parse( src => "hi", expect => [qr/\# header/] );
}

1;
