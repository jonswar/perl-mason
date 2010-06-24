package Mason::Interp;
use File::Basename;
use File::Spec::Functions qw(canonpath catdir catfile);
use Guard;
use Mason::Compiler;
use Mason::Request;
use Mason::Util;
use Memoize;
use Moose::Util::TypeConstraints;
use Moose;
use MooseX::StrictConstructor;
use autodie qw(:all);
use strict;
use warnings;

subtype 'Mason::Types::CompRoot' => as 'ArrayRef[Str]';
coerce 'Mason::Types::CompRoot' => from 'Str' => via { [$_] };

subtype 'Mason::Types::OutMethod' => as 'CodeRef';
coerce 'Mason::Types::OutMethod' => from 'ScalarRef' => via {
    my $ref = $_;
    sub { $$ref .= $_[0] }
};

my $default_out = sub { print( $_[0] ) };
my $interp_id = 0;

# Passed attributes
has 'autohandler_name' => ( is => 'ro', default    => 'autohandler' );
has 'comp_root'        => ( is => 'ro', isa        => 'Mason::Types::CompRoot', coerce => 1 );
has 'compiler'         => ( is => 'ro', lazy_build => 1 );
has 'compiler_class'   => ( is => 'ro', default    => 'Mason::Compiler' );
has 'chi_root_class'        => ( is => 'ro' );
has 'data_dir'              => ( is => 'ro' );
has 'dhandler_name'         => ( is => 'ro' );
has 'max_recurse'           => ( is => 'ro' );
has 'object_file_extension' => ( is => 'ro', default => '.obj.pl' );
has 'out_method' =>
  ( is => 'ro', isa => 'Mason::Types::OutMethod', default => sub { $default_out }, coerce => 1 );
has 'request_class' => ( is => 'ro', default => 'Mason::Request' );
has 'resolver'      => ( is => 'ro' );
has 'static_source' => ( is => 'ro' );
has 'static_source_touch_file' => ( is => 'ro' );

# Derived attributes
has 'code_cache' => ( is => 'ro', init_arg => undef );
has 'id'         => ( is => 'ro', init_arg => undef );

__PACKAGE__->meta->make_immutable();

sub BUILD {
    my ( $self, $params ) = @_;

    $self->{code_cache} = {};
    $self->{id}         = $interp_id++;

    if ( $self->{static_source} ) {
        $self->{static_source_touch_file_lastmod} = 0;
        $self->{static_source_touch_file} ||= catfile( $self->data_dir, 'purge.dat' );
        $self->{use_internal_component_caches} = 1;
    }

    # Separate out compiler parameters
    #
    $self->{compiler_params} = {};
    my %is_compiler_attribute = map { ( $_, 1 ) } $self->compiler_class->meta->get_attribute_list();

    foreach my $key ( keys(%$params) ) {
        if ( $is_compiler_attribute{$key} ) {
            $self->{compiler_params}->{$key} = delete( $params->{$key} );
        }
    }
}

sub _build_compiler {
    my $self = shift;
    return $self->compiler_class->new( %{ $self->{compiler_params} } );
}

sub run {
    my $self    = shift;
    my $path    = shift;
    my $request = $self->build_request();
    $request->run( $path, @_ );
}

sub srun {
    my $self = shift;
    my $output;
    local $self->{out_method} = sub { $output .= $_[0] };
    $self->run(@_);
    return $output;
}

sub build_request {
    my $self = shift;
    return $self->request_class->new( interp => $self );
}

# Loads the component in $path; returns a component class, or undef if not
# found. Memoize the results - this helps both with components used multiple
# times in a request, and with determining default parent components.
# The memoize cache is cleared at the beginning of each request, or in
# static_source_mode, when the purge file is touched.
#
memoize('load');

sub flush_load_cache {
    Memoize::flush_cache('load');
}

sub load {
    my ( $self, $path ) = @_;

    # Canonicalize path
    #
    $path = Mason::Util::mason_canon_path($path);

    # Split path into dir_path and base_name - validate that it has a
    # starting slash and ends with at least one non-slash character
    #
    my ( $dir_path, $base_name ) = ( $path =~ m{^(/.*?)/?([^/]+)$} )
      or die "not a valid absolute component path - '$path'";

    # Determine default parent component class for component
    #
    my $default_parent_compc =
      $self->load_upwards( $dir_path, 'autohandler', $base_name eq 'autohandler' ? 1 : 0 )
      || 'Mason::Component';

    # Resolve path to source file
    #
    my $source_file = $self->source_file_for_path($path)
      or return undef;
    my $source_lastmod = ( stat($source_file) )[9];

    # If code cache contains an entry for this source file and it is up to
    # date, return the cached comp.
    #
    my $code_cache = $self->code_cache;
    if ( my $entry = $code_cache->{$source_file} ) {
        if (   $entry->{source_lastmod} >= $source_lastmod
            && $entry->{default_parent_compc} eq $default_parent_compc )
        {
            return $entry->{compc};
        }
        else {

            # Delete old package (by freeing guard) and delete cache entry
            #
            undef $entry->{guard};
            delete $code_cache->{$source_file};
        }
    }

    # Determine object file and its last modified time
    #
    my $object_file = $self->object_file_for_path($path);
    my @stat        = stat $object_file;
    if ( @stat && !-f _ ) {
        die "The object file '$object_file' exists but it is not a file!";
    }
    my $object_lastmod = @stat ? $stat[9] : 0;
    if ( $object_lastmod < $source_lastmod && !$self->static_source ) {
        $self->compiler->compile_to_file( $source_file, $path, $object_file );
    }

    my $compc = $self->comp_class_for_path($path);

    $self->load_class_from_object_file( $compc, $default_parent_compc, $object_file );

    # Save component class in the cache.
    #
    my $guard = guard { Mason::Util::delete_package($compc) };
    $code_cache->{$source_file} = {
        source_lastmod       => $source_lastmod,
        default_parent_compc => $default_parent_compc,
        compc                => $compc,
        guard                => $guard
    };

    return $compc;
}

sub load_class_from_object_file {
    my ( $self, $compc, $default_parent_compc, $object_file ) = @_;

    eval(
        sprintf(
            'package %s; use Moose; extends "%s"; do("%s"); die $@ if $@',
            $compc, $default_parent_compc, $object_file
        )
    );
    die $@ if $@;

    unless ( $compc->meta->has_method('render') ) {
        $compc->meta->add_augment_method_modifier(
            render => sub { my $self = shift; $self->main(@_) } );
    }
}

# Search for component <name> in the parents of <dir_path>. Return the
# component class or undef if we reach '/'. Skip <skip> initial directories.
#
our $depth = 0;

sub load_upwards {
    my ( $self, $dir_path, $name, $skip ) = @_;

    local $depth = $depth + 1;
    die "blah" if $depth > 10;
    if ($skip) {
        $skip--;
    }
    elsif ( my $compc = $self->load( $dir_path . ( $dir_path eq '/' ? '' : '/' ) . $name ) ) {
        return $compc;
    }
    if ( $dir_path eq '/' ) {
        return undef;
    }
    else {
        $dir_path = dirname($dir_path);
        return $self->load_upwards( $dir_path, $name, $skip, $depth + 1 );
    }
}

sub source_file_for_path {
    my ( $self, $path ) = @_;

    foreach my $root_path ( @{ $self->comp_root } ) {
        my $source_file = $root_path . $path;
        return $source_file if -f $source_file;
    }
    return undef;
}

sub object_file_for_path {
    my ( $self, $path ) = @_;

    return catfile( $self->object_dir, $self->compiler->compiler_id, ( split /\//, $path ), )
      . $self->object_file_extension;
}

sub comp_class_for_path {
    my ( $self, $path ) = @_;

    my $classname = substr( $path, 1 );
    $classname =~ s/[^\w]/_/g;
    $classname =~ s/\//::/g;
    $classname = "MC" . $self->id . "::" . $classname;
    return $classname;
}

sub object_create_marker_file {
    my $self = shift;
    return catfile( $self->object_dir, '.__obj_create_marker' );
}

sub object_dir {
    my $self = shift;
    return catdir( $self->data_dir, 'obj' );
}

sub _make_object_dir {
    my ($self) = @_;

    my $object_dir = $self->object_dir;
    if ( !-f $object_dir ) {
        make_path($object_dir);
        my $object_create_marker_file = $self->object_create_marker_file;
        write_file( $object_create_marker_file, "" )
          unless -f $object_create_marker_file;
    }
}

# Check the static_source_touch_file, if one exists, to see if it has
# changed since we last checked. If it has, clear the code cache and
# object files if appropriate.
#
sub check_static_source_touch_file {
    my $self = shift;

    if ( my $touch_file = $self->static_source_touch_file ) {
        return unless -f $touch_file;
        my $touch_file_lastmod = ( stat($touch_file) )[9];
        if ( $touch_file_lastmod > $self->{static_source_touch_file_lastmod} ) {

            # File has been touched since we last checked.  First,
            # clear the object file directory if the last mod of
            # its ._object_create_marker is earlier than the touch file,
            # or if the marker doesn't exist.
            #
            if ( $self->use_object_files ) {
                my $object_create_marker_file = $self->object_create_marker_file;
                if ( !-e $object_create_marker_file
                    || ( stat($object_create_marker_file) )[9] < $touch_file_lastmod )
                {
                    $self->remove_object_files;
                }
            }

            # Next, clear the in-memory component cache.
            #
            $self->flush_code_cache;

            # Reset lastmod value.
            #
            $self->{static_source_touch_file_lastmod} = $touch_file_lastmod;
        }
    }
}

1;
