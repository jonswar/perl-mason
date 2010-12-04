package Mason::Test::Class;
use Carp;
use File::Basename;
use File::Path;
use File::Slurp;
use File::Temp qw(tempdir);
use Mason::Interp;
use Method::Signatures::Simple;
use Test::Exception;
use Test::More;
use strict;
use warnings;
use base qw(Test::Class);

__PACKAGE__->SKIP_CLASS("abstract base class");

my $gen_path_count = 0;
my $temp_dir_count = 0;

sub _startup : Test(startup) {
    my $self = shift;
    $self->{temp_root} = tempdir( 'mason-test-XXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->setup_dirs;
}

sub setup_dirs {
    my $self = shift;

    $self->{temp_dir}  = join( "/", $self->{temp_root}, $temp_dir_count++ );
    $self->{comp_root} = $self->{temp_dir} . "/comps";
    $self->{data_dir}  = $self->{temp_dir} . "/data";
    mkpath( [ $self->{comp_root}, $self->{data_dir} ], 0, 0775 );

    $self->{interp} = Mason::Interp->new(
        comp_root => $self->{comp_root},
        data_dir  => $self->{data_dir},
    );
}

method add_comp (%params) {
    my $path   = $params{path}      || die "must pass path";
    my $source = $params{component} || die "must pass component";
    die "'$path' is not absolute" unless substr( $path, 0, 1 ) eq '/';
    my $source_file = $self->{comp_root} . $path;
    $self->mkpath_and_write_file( $source_file, $source );
}

method remove_comp (%params) {
    my $path = $params{path} || die "must pass path";
    my $source_file = join( "/", $self->{comp_root}, $path );
    unlink($source_file);
}

method test_comp (%params) {
    my $caller = ( caller(1) )[3];
    my ($caller_base) = ( $caller =~ /([^:]+)$/ );
    my $path         = $params{path} || ( "/$caller_base" . ( ++$gen_path_count ) );
    my $desc         = $params{desc};
    my $source       = $params{component} || croak "must pass component";
    my $expect       = $params{expect};
    my $expect_error = $params{expect_error};
    croak "must pass either expect or expect_error" unless $expect || $expect_error;

    ( my $run_path = $path ) =~ s/\.m$//;
    $path .= ".m" if $path !~ /\.m$/;

    $self->add_comp( path => $path, component => $source );
    if ($expect_error) {
        $desc ||= $expect_error;
        throws_ok( sub { $self->{interp}->srun($run_path) }, $expect_error, $desc );
    }
    else {
        $desc ||= $caller;
        is( $self->{interp}->srun($run_path), $expect, $desc );
    }
}

method mkpath_and_write_file ( $source_file, $source ) {
    unlink($source_file) if -e $source_file;
    mkpath( dirname($source_file), 0, 0775 );
    write_file( $source_file, $source );
}

1;
