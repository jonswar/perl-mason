package Mason::Interp;
use File::Basename;
use File::Spec::Functions qw(canonpath catdir catfile);
use Guard;
use List::Util qw(first);
use Mason::Compiler;
use Mason::Request;
use Mason::Types;
use Mason::Util qw(mason_canon_path);
use Memoize;
use Method::Signatures::Simple;
use Moose::Util::TypeConstraints;
use Moose;
use Mason::Moose;
use MooseX::StrictConstructor;
use JSON;
use autodie qw(:all);
use strict;
use warnings;

my $default_out = sub { print( $_[0] ) };
my $interp_id = 0;

# Passed attributes
has 'autohandler_names'        => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'comp_root'                => ( isa        => 'Mason::Types::CompRoot', coerce => 1 );
has 'compiler'                 => ( lazy_build => 1 );
has 'compiler_class'           => ( lazy_build => 1 );
has 'component_class_prefix'   => ( lazy_build => 1 );
has 'component_base_class'     => ( default    => 'Mason::Component' );
has 'chi_root_class'           => ( is => 'ro' );
has 'data_dir'                 => ( is => 'ro' );
has 'dhandler_names'           => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'mason_root_class'         => ( is => 'ro', required => 1 );
has 'object_file_extension'    => ( default => '.obj.pm' );
has 'request_class'            => ( lazy_build => 1 );
has 'request_count'            => ( is => 'ro', default => 0, reader => { request_count => sub { $_[0]->{request_count}++ } } );
has 'static_source'            => ( is => 'ro' );
has 'static_source_touch_file' => ( is => 'ro' );
has 'top_level_extensions'     => ( isa => 'ArrayRef[Str]', default => sub { [ '.pm', '.m' ] } );

# Derived attributes
has 'autohandler_or_dhandler_regex' => ( lazy_build => 1 );
has 'code_cache'             => ( init_arg => undef );
has 'compiler_params'        => ( init_arg => undef );
has 'default_request_params' => ( init_arg => undef );
has 'id'                     => ( init_arg => undef );

method BUILD ($params) {
    $self->{code_cache} = {};
    $self->{id}         = $interp_id++;

    if ( $self->{static_source} ) {
        $self->{static_source_touch_file_lastmod} = 0;
        $self->{static_source_touch_file} ||= catfile( $self->data_dir, 'purge.dat' );
    }

    # Separate out compiler and request parameters
    #
    $self->{compiler_params} = {};
    my %is_compiler_attribute =
      map { ( $_, 1 ) } $self->compiler_class->meta->get_attribute_list();
    foreach my $key ( keys(%$params) ) {
        if ( $is_compiler_attribute{$key} ) {
            $self->{compiler_params}->{$key} = delete( $params->{$key} );
        }
    }
    $self->{default_request_params} = {};
    my %is_request_attribute =
      map { ( $_, 1 ) } $self->compiler_class->meta->get_attribute_list();
    foreach my $key ( keys(%$params) ) {
        if ( $is_request_attribute{$key} ) {
            $self->{default_request_params}->{$key} = delete( $params->{$key} );
        }
    }
}

method _build_autohandler_names () {
    return [ map { "autohandler" . $_ } @{ $self->top_level_extensions } ];
}

method _build_autohandler_or_dhandler_regex () {
    my $regex = '(' . join( "|", @{ $self->autohandler_names }, @{ $self->dhandler_names } ) . ')$';
    return qr/$regex/;
}

method _build_compiler () {
    return $self->compiler_class->new( %{ $self->compiler_params } );
}

method _build_compiler_class () {
    return $self->mason_root_class->find_subclass('Compiler');
}

method _build_component_class_prefix () {
    return "MC" . $self->{id};
}

method _build_dhandler_names () {
    return [ map { "dhandler" . $_ } @{ $self->top_level_extensions } ];
}

method _build_request_class () {
    return $self->mason_root_class->find_subclass('Request');
}

method run () {
    my %request_params;
    while ( ref( $_[0] ) eq 'HASH' ) {
        %request_params = ( %request_params, %{ shift(@_) } );
    }
    my $path    = shift;
    my $request = $self->build_request(%request_params);
    $request->run( $path, @_ );
}

method srun () {
    $self->run( { out_method => \my $output }, @_ );
    return $output;
}

method build_request () {
    return $self->request_class->new( interp => $self, %{ $self->default_request_params }, @_ );
}

method flush_load_cache () {
    Memoize::flush_cache('load');
}

# Loads the component in $path; returns a component class, or undef if not
# found. Memoize the results - this helps both with components used multiple
# times in a request, and with determining default parent components.
# The memoize cache is cleared at the beginning of each request, or in
# static_source_mode, when the purge file is touched.
#
method load ($path) {

    # Canonicalize path
    #
    $path = Mason::Util::mason_canon_path($path);

    # Resolve path to source file
    #
    my $source_file = $self->source_file_for_path($path)
      or return undef;
    my $source_lastmod = ( stat($source_file) )[9];

    # Determine default parent comp
    #
    my $default_parent_compc = $self->default_parent_compc($path);

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
        die "'$object_file' exists but it is not a file!";
    }
    my $object_lastmod = @stat ? $stat[9] : 0;
    if ( !$object_lastmod || ( $object_lastmod < $source_lastmod && !$self->static_source ) ) {
        $self->compiler->compile_to_file( $self, $source_file, $path, $object_file );
    }

    my $compc = $self->comp_class_for_path($path);

    $self->load_class_from_object_file( $compc, $object_file, $path, $default_parent_compc );

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

memoize('load');

method load_class_from_object_file ( $compc, $object_file, $path, $default_parent_compc ) {
    my $parent_compc = $self->determine_parent_compc_from_object_file( $object_file, $path )
      || $default_parent_compc;
    eval(
        sprintf(
            'package %s; use Moose; extends "%s"; do("%s"); die $@ if $@',
            $compc, $parent_compc, $object_file
        )
    );
    die $@ if $@;

    unless ( $compc->meta->has_method('render') ) {
        $compc->meta->add_augment_method_modifier(
            render => sub { my $self = shift; $self->main(@_) } );
    }
}

method determine_parent_compc_from_object_file ($object_file, $path) {
    my $flags = $self->extract_flags_from_object_file($object_file);
    my $parent_compc;
    if ( exists( $flags->{extends} ) ) {
        my $extends = $flags->{extends};
        if ( defined($extends) ) {
            $extends = mason_canon_path( join( "/", dirname($path), $extends ) )
              if substr( $extends, 0, 1 ) ne '/';
            $parent_compc = $self->load($extends)
              or die "could not load '$extends' for extends flag";
        }
        else {
            $parent_compc = $self->component_base_class;
        }
    }
    return $parent_compc;
}

method extract_flags_from_object_file ($object_file) {
    my $flags = {};
    open( my $fh, "<", $object_file );
    my $line = <$fh>;
    if ( my ($flags_str) = ( $line =~ /\# FLAGS: (.*)/ ) ) {
        $flags = JSON->new->decode($flags_str);
    }
    return $flags;
}

# Given /foo/bar.m, look for (by default):
#   /foo/autohandler.pm, /foo/autohandler.m,
#   /autohandler.pm, /autohandler.m
#
method default_parent_compc ($path) {

    # Split path into dir_path and base_name - validate that it has a
    # starting slash and ends with at least one non-slash character
    #
    my ( $dir_path, $base_name ) = ( $path =~ m{^(/.*?)/?([^/]+)$} )
      or die "not a valid absolute component path - '$path'";
    $path = $dir_path;

    my @autohandler_subpaths = map { "/$_" } @{ $self->autohandler_names };
    my $skip = ( grep { $_ eq $base_name } @{ $self->autohandler_names } ) ? 1 : 0;
    while (1) {
        if ($skip) {
            $skip--;
        }
        else {
            my @candidates =
              ( $path eq '/' )
              ? @autohandler_subpaths
              : ( map { $path . $_ } @autohandler_subpaths );
            foreach my $candidate (@candidates) {
                if ( my $compc = $self->load($candidate) ) {
                    return $compc;
                }
            }
        }
        if ( $path eq '/' ) {
            return $self->component_base_class;
        }
        $path = dirname($path);
    }
}

method source_file_for_path ($path) {
    foreach my $root_path ( @{ $self->comp_root } ) {
        my $source_file = $root_path . $path;
        return $source_file if -f $source_file;
    }
    return undef;
}

method object_file_for_path ($path) {
    return catfile( $self->object_dir, $self->compiler->compiler_id, ( split /\//, $path ), )
      . $self->object_file_extension;
}

method comp_class_for_path ($path) {
    my $classname = substr( $path, 1 );
    $classname =~ s/[^\w]/_/g;
    $classname =~ s/\//::/g;
    $classname = join( "::", $self->component_class_prefix, $classname );
    return $classname;
}

method object_create_marker_file () {
    return catfile( $self->object_dir, '.__obj_create_marker' );
}

method object_dir () {
    return catdir( $self->data_dir, 'obj' );
}

method _make_object_dir () {
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
method check_static_source_touch_file () {
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

__PACKAGE__->meta->make_immutable();

1;
