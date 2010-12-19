package Mason::Test::Class;
use Carp;
use File::Basename;
use File::Path;
use File::Slurp;
use File::Temp qw(tempdir);
use Mason;
use Mason::Util qw(trim);
use Method::Signatures::Simple;
use Test::Exception;
use Test::LongString;
use Test::More;
use strict;
use warnings;
use base qw(Test::Class);

__PACKAGE__->SKIP_CLASS("abstract base class");

my $gen_path_count = 0;
my $parse_count    = 0;
my $temp_dir_count = 0;

sub _startup : Test(startup) {
    my $self = shift;
    $self->{temp_root} = tempdir( 'mason-test-XXXX', TMPDIR => 1, CLEANUP => 0 );
    $self->setup_dirs;
}

method setup_dirs () {
    $self->{temp_dir}  = join( "/", $self->{temp_root}, $temp_dir_count++ );
    $self->{comp_root} = $self->{temp_dir} . "/comps";
    $self->{data_dir}  = $self->{temp_dir} . "/data";
    mkpath( [ $self->{comp_root}, $self->{data_dir} ], 0, 0775 );

    $self->{interp} = $self->create_interp();
}

method create_interp () {
    return Mason->new(
        comp_root => $self->{comp_root},
        data_dir  => $self->{data_dir},
        @_
    );
}

method add_comp (%params) {
    my $path    = $params{path}      || die "must pass path";
    my $source  = $params{component} || die "must pass component";
    my $verbose = $params{v}         || $params{verbose};
    die "'$path' is not absolute" unless substr( $path, 0, 1 ) eq '/';
    my $source_file = $self->{comp_root} . $path;
    $self->mkpath_and_write_file( $source_file, $source );
    if ($verbose) {
        print STDERR "*** $path ***\n";
        my $output = $self->{interp}->compiler->compile( $source_file, $path );
        print STDERR "$output\n";
    }
}

method remove_comp (%params) {
    my $path = $params{path} || die "must pass path";
    my $source_file = join( "/", $self->{comp_root}, $path );
    unlink($source_file);
}

method test_comp (%params) {
    my $caller = ( caller(1) )[3];
    my ($caller_base) = ( $caller =~ /([^:]+)$/ );
    my $path         = $params{path} || ( "/$caller_base" . ( ++$gen_path_count ) . ".m" );
    my $desc         = $params{desc};
    my $source       = $params{component} || croak "must pass component";
    my $expect       = trim( $params{expect} );
    my $expect_error = $params{expect_error};
    my $verbose      = $params{v} || $params{verbose};
    croak "must pass either expect or expect_error" unless $expect || $expect_error;

    ( my $run_path = $path ) =~ s/\.(?:m|pm)$//;

    $self->add_comp( path => $path, component => $source, verbose => $verbose );

    if ($expect_error) {
        $desc ||= $expect_error;
        throws_ok( sub { $self->{interp}->srun($run_path) }, $expect_error, $desc );
    }
    else {
        $desc ||= $caller;
        my $output = trim( $self->{interp}->srun($run_path) );
        is( $output, $expect, $desc );
    }
}

method test_parse (%params) {
    my $caller = ( caller(1) )[3];
    my ($caller_base) = ( $caller =~ /([^:]+)$/ );
    my $desc = $params{desc};
    my $source       = $params{component} || croak "must pass component";
    my $expect_list  = $params{expect};
    my $expect_error = $params{expect_error};
    croak "must pass either expect or expect_error" unless $expect_list || $expect_error;

    my $path = "/parse/comp" . $parse_count++;
    my $file = $self->{temp_dir} . $path;
    $self->mkpath_and_write_file( $file, $source );

    if ($expect_error) {
        $desc ||= $expect_error;
        throws_ok( sub { $self->{interp}->compiler->compile( $file, $path ) },
            $expect_error, $desc );
    }
    else {
        $desc ||= $caller;
        my $output = $self->{interp}->compiler->compile( $file, $path );
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
