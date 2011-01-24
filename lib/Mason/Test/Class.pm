package Mason::Test::Class;
use Carp;
use File::Basename;
use File::Path;
use File::Temp qw(tempdir);
use Mason;
use Mason::Util qw(trim write_file);
use Method::Signatures::Simple;
use Test::Class::Most;
use Test::LongString;
use strict;
use warnings;

__PACKAGE__->SKIP_CLASS("abstract base class");

# RO accessors
sub comp_root { $_[0]->{comp_root} }
sub data_dir  { $_[0]->{data_dir} }
sub interp    { $_[0]->{interp} }
sub temp_dir  { $_[0]->{temp_dir} }
sub temp_root { $_[0]->{temp_root} }

# RW class accessors
my $default_plugins = [];
sub default_plugins { $default_plugins = $_[1] if defined( $_[1] ); $default_plugins }

my $gen_path_count = 0;
my $parse_count    = 0;
my $temp_dir_count = 0;

our $current_test_object;

sub _startup : Test(startup) {
    my $self    = shift;
    my $verbose = $ENV{TEST_VERBOSE};
    $self->{temp_root} = tempdir( 'mason-test-XXXX', TMPDIR => 1, CLEANUP => $verbose ? 0 : 1 );
    printf STDERR ( "\n*** temp_root = %s, no cleanup\n", $self->{temp_root} ) if $verbose;
    $self->setup_dirs;
}

method setup_dirs () {
    $self->{temp_dir}  = join( "/", $self->{temp_root}, $temp_dir_count++ );
    $self->{comp_root} = $self->{temp_dir} . "/comps";
    $self->{data_dir}  = $self->{temp_dir} . "/data";
    mkpath( [ $self->{comp_root}, $self->{data_dir} ], 0, 0775 );
    $self->setup_interp(@_);
}

method setup_interp () {
    $self->{interp} = $self->create_interp(@_);
}

method create_interp () {
    my (%params) = @_;
    $params{plugins} = $default_plugins if @$default_plugins;
    return Mason->new(
        comp_root              => $self->comp_root,
        data_dir               => $self->data_dir,
        no_source_line_numbers => 1,
        %params,
    );
}

method add_comp (%params) {
    my $path    = $params{path} || die "must pass path";
    my $source  = $params{src}  || die "must pass src";
    my $verbose = $params{v}    || $params{verbose};
    die "'$path' is not absolute" unless substr( $path, 0, 1 ) eq '/';
    my $source_file = $self->comp_root . $path;
    $self->mkpath_and_write_file( $source_file, $source );
    if ($verbose) {
        print STDERR "*** $path ***\n";
        my $output = $self->interp->compile( $source_file, $path );
        print STDERR "$output\n";
    }
}

method remove_comp (%params) {
    my $path = $params{path} || die "must pass path";
    my $source_file = join( "/", $self->comp_root, $path );
    unlink($source_file);
}

method test_comp (%params) {
    my $caller = ( caller(1) )[3];
    my ($caller_base) = ( $caller =~ /([^:]+)$/ );
    my $path   = $params{path} || ( "/$caller_base" . ( ++$gen_path_count ) . ".m" );
    my $args   = $params{args} || {};
    my $desc   = $params{desc} || $path;
    my $source = $params{src}  || croak "must pass src";
    my $expect = trim( $params{expect} );
    my $expect_error = $params{expect_error};
    my $verbose = $params{v} || $params{verbose};

    $self->add_comp( path => $path, src => $source, verbose => $verbose );
    my $run_path = $path;

    my @run_params = ( $run_path, %$args );
    local $current_test_object = $self;

    if ( defined($expect_error) ) {
        $desc ||= $expect_error;
        throws_ok( sub { $self->interp->run(@run_params) }, $expect_error, $desc );
    }
    elsif ( defined($expect) ) {
        $desc ||= $caller;
        my $output = trim( $self->interp->run(@run_params)->output );
        if ( ref($expect) eq 'Regexp' ) {
            like( $output, $expect, $desc );
        }
        else {
            is( $output, $expect, $desc );
        }
    }
}

method run_test_in_comp (%params) {
    my $test = delete( $params{test} ) || die "must pass test";
    my $args = delete( $params{args} ) || {};
    $self->add_comp( %params, src => '% $.cmeta->args->{_test}->($self);' );
    my $run_path = $params{path};
    my @run_params = ( $run_path, %$args );
    $self->interp->run( @run_params, _test => $test );
}

method test_parse (%params) {
    my $caller = ( caller(1) )[3];
    my ($caller_base) = ( $caller =~ /([^:]+)$/ );
    my $desc = $params{desc};
    my $source       = $params{src} || croak "must pass src";
    my $expect_list  = $params{expect};
    my $expect_error = $params{expect_error};
    croak "must pass either expect or expect_error" unless $expect_list || $expect_error;

    my $path = "/parse/comp" . $parse_count++;
    my $file = $self->temp_dir . $path;
    $self->mkpath_and_write_file( $file, $source );

    if ($expect_error) {
        $desc ||= $expect_error;
        throws_ok( sub { $self->interp->compile( $file, $path ) }, $expect_error, $desc );
    }
    else {
        $desc ||= $caller;
        my $output = $self->interp->compile( $file, $path );
        foreach my $expect (@$expect_list) {
            if ( ref($expect) eq 'Regexp' ) {
                like_string( $output, $expect, "$desc - $expect" );
            }
            else {
                contains_string( $output, $expect, "$desc - $expect" );
            }
        }
    }
}

method mkpath_and_write_file ( $source_file, $source ) {
    unlink($source_file) if -e $source_file;
    mkpath( dirname($source_file), 0, 0775 );
    write_file( $source_file, $source );
}

1;
