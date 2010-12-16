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
has 'autobase_names'           => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'comp_root'                => ( isa        => 'Mason::Types::CompRoot', coerce => 1 );
has 'compiler'                 => ( lazy_build => 1 );
has 'compiler_class'           => ( lazy_build => 1 );
has 'component_class_prefix'   => ( lazy_build => 1 );
has 'component_base_class'     => ( lazy_build => 1 );
has 'chi_root_class'           => ( default => 'CHI' );
has 'chi_default_params'       => ( lazy_build => 1 );
has 'data_dir'                 => ( );
has 'dhandler_names'           => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'index_names'              => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'mason_root_class'         => ( required => 1 );
has 'object_file_extension'    => ( default => '.mobj' );
has 'plugins'                  => ( default => sub { [] } );
has 'request_class'            => ( lazy_build => 1 );
has 'static_source'            => ( );
has 'static_source_touch_file' => ( );
has 'top_level_extensions'     => ( isa => 'ArrayRef[Str]', default => sub { [ '.pm', '.m' ] } );

# Derived attributes
has 'autobase_regex'                => ( lazy_build => 1, init_arg => undef );
has 'autobase_or_dhandler_regex'    => ( lazy_build => 1, init_arg => undef );
has 'code_cache'                    => ( init_arg => undef );
has 'compiler_params'               => ( init_arg => undef );
has 'request_params'                => ( init_arg => undef );
has 'id'                            => ( init_arg => undef );
has 'request_count'                 => ( init_arg => undef, default => 0, reader => { request_count => sub { $_[0]->{request_count}++ } } );

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
    $self->{request_params} = {};
    my %is_request_attribute =
      map { ( $_, 1 ) } $self->compiler_class->meta->get_attribute_list();
    foreach my $key ( keys(%$params) ) {
        if ( $is_request_attribute{$key} ) {
            $self->{request_params}->{$key} = delete( $params->{$key} );
        }
    }
}

method _build_autobase_or_dhandler_regex () {
    my $regex = '(' . join( "|", @{ $self->autobase_names }, @{ $self->dhandler_names } ) . ')$';
    return qr/$regex/;
}

method _build_autobase_names () {
    return [ map { "Base" . $_ } @{ $self->top_level_extensions } ];
}

method _build_autobase_regex () {
    my $regex = '(' . join( "|", @{ $self->autobase_names } ) . ')$';
    return qr/$regex/;
}

method _build_chi_default_params () {
    return {
        driver   => 'File',
        root_dir => catdir( $self->data_dir, 'cache' )
    };
}

method _build_compiler () {
    return $self->compiler_class->new( interp => $self, %{ $self->compiler_params } );
}

method _build_compiler_class () {
    return $self->find_subclass('Compiler');
}

method _build_component_base_class () {
    return $self->find_subclass('Component');
}

method _build_component_class_prefix () {
    return "MC" . $self->{id};
}

method _build_dhandler_names () {
    return [ map { "dhandler" . $_ } @{ $self->top_level_extensions } ];
}

method _build_index_names () {
    return [ map { "index" . $_ } @{ $self->top_level_extensions } ];
}

method _build_request_class () {
    return $self->find_subclass('Request');
}

method find_subclass ($name) {
    return $self->mason_root_class->find_subclass( $name, $self->plugins );
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
    return $self->request_class->new( interp => $self, %{ $self->request_params }, @_ );
}

method flush_load_cache () {
    Memoize::flush_cache('load');
}

method comp_exists ($path) {
    return $self->source_file_for_path( Mason::Util::mason_canon_path($path) );
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
        $self->compiler->compile_to_file( $source_file, $path, $object_file );
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
    my $flags = $self->extract_flags_from_object_file($object_file);
    my $parent_compc = $self->determine_parent_compc( $path, $flags )
      || $default_parent_compc;
    eval(
        sprintf(
            'package %s; use Moose; extends "%s"; do("%s"); die $@ if $@',
            $compc, $parent_compc, $object_file
        )
    );
    die $@ if $@;

    $self->add_default_render_method( $compc, $flags );
}

# Default render method for any component that doesn't define one.
# Call inner() until we're back down at the page component ($self),
# then call main().
#
method add_default_render_method ($compc, $flags) {
    unless ( $compc->meta->has_method('render') ) {
        my $path = $compc->comp_path;
        my $code = sub {
            my $self = shift;
            if ( $self->comp_path eq $path ) {
                $self->main(@_);
            }
            else {
                $compc->comp_inner();
            }
        };
        my $meta = $compc->meta;
        if ( $flags->{ignore_wrap} ) {
            $meta->add_method( render => $code );
        }
        else {
            $meta->add_augment_method_modifier( render => $code );
        }
    }
}

method determine_parent_compc ($path, $flags) {
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
#   /foo/Base.pm, /foo/Base.m,
#   /Base.pm, /Base.m
#
method default_parent_compc ($path) {

    # Split path into dir_path and base_name - validate that it has a
    # starting slash and ends with at least one non-slash character
    #
    my ( $dir_path, $base_name ) = ( $path =~ m{^(/.*?)/?([^/]+)$} )
      or die "not a valid absolute component path - '$path'";
    $path = $dir_path;

    my @autobase_subpaths = map { "/$_" } @{ $self->autobase_names };
    my $skip = ( grep { $_ eq $base_name } @{ $self->autobase_names } ) ? 1 : 0;
    while (1) {
        if ($skip) {
            $skip--;
        }
        else {
            my @candidates =
              ( $path eq '/' )
              ? @autobase_subpaths
              : ( map { $path . $_ } @autobase_subpaths );
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
    die "'$path' is not an absolute path" unless substr( $path, 0, 1 ) eq '/';
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

__END__

=head1 NAME

Mason::Interp - Mason Interpreter

=head1 SYNOPSIS

    my $i = Mason->new (comp_root => '/path/to/comps',
                        data_dir  => '/path/to/data',
                        ...);

=head1 DESCRIPTION

Interp is the central Mason object, returned from C<< Mason->new >>. It is
responsible for creating new Request objects and maintaining the cache of
loaded components.

=head1 PARAMETERS TO THE new() CONSTRUCTOR

=over

=item autobase_names

Array reference of L<autobase|Mason::Manual/Autobase components> filenames to
check in order when determining a component's superclass. Default is
["Base.pm", "Base.m"].

=item comp_root

The component root marks the top of your component hierarchy and defines how
component paths are translated into real file paths. For example, if your
component root is F</usr/local/httpd/docs>, a component path of
F</products/index.html> translates to the file
F</usr/local/httpd/docs/products/index.html>.

This parameter may be either a scalar or an array reference.  If it is a
scalar, it should be a filesystem path indicating the component root. If it is
an array reference, it should be of the following form:

 [ [ foo => '/usr/local/foo' ],
   [ bar => '/usr/local/bar' ] ]

This is an array of two-element array references, not a hash.  The "keys" for
each path must be unique and their "values" must be filesystem paths.  These
paths will be searched in the provided order whenever a component path is
resolved. For example, given the above component roots and a component path of
F</products/index.html>, Mason would search first for
F</usr/local/foo/products/index.html>, then for
F</usr/local/bar/products/index.html>.

The keys are used in several ways. They help to distinguish component caches
and object files between different component roots, and they appear in the
C<title()> of a component.

When you specify a single path for a component root, this is actually
translated into

  [ [ MAIN => path ] ]

=item compiler

The Compiler object to associate with this Interpreter.  By default a new
object of class L</compiler_class> will be created.

=item compiler_class

The class to use when creating a compiler. Defaults to
L<Mason::Compiler|Mason::Compiler>.

=item component_class_prefix

Prefix to use in generated component classnames. Defaults to 'MC' plus a unique
number for the interpreter, e.g. MC0. So a component '/foo/bar' would get a
classname like 'MC0::foo::bar'.

=item component_base_class

The base class for components that do not inherit from another component.
Defaults to L<Mason::Component|Mason::Component>.

=item chi_default_params

A hashref of parameters that L<$m-E<gt>cache|cache> should pass to each cache
constructor. Defaults to C<< { driver => 'File', root_dir => 'DATA_DIR/cache' }
>>.

=item chi_root_class

The class that L<$m-E<gt>cache|cache> should use for creating cache objects.
Defaults to 'CHI'.

=item data_dir

The data directory is a writable directory that Mason uses for various features
and optimizations: for example, component object files and data cache files.
Mason will create the directory on startup if necessary.

=item dhandler_names

Array reference of dhandler file names to check in order when resolving a
top-level path. Default is C<< ["dhandler.pm", "dhandler.m"] >>. See
L<Mason::Manual/Determining the page component>.

=item index_names

Array reference of index file names to check in order when resolving a
top-level path (only in the bottom-most directory). Default is C<< ["index.pm",
"index.m"] >>. See L<Mason::Manual/Determining the page component>.

=item object_file_extension

Extension to add to the end of object files. Default is ".mobj".

=item request_class

The class to use when creating requests. Defaults to
L<Mason::Request|Mason::Request>.

=item static_source

True or false, default is false. When false, Mason checks the timestamp of the
component source file each time the component is used to see if it has changed.
This provides the instant feedback for source changes that is expected for
development.  However it does entail a file stat for each component executed.

When true, Mason assumes that the component source tree is unchanging: it will
not check component source files to determine if the memory cache or object
file has expired.  This can save many file stats per request. However, in order
to get Mason to recognize a component source change, you must flush the memory
cache and remove object files. See L</static_source_touch_file> for one easy
way to arrange this.

We recommend turning this mode on in your production sites if possible, if
performance is of any concern.

=item static_source_touch_file

Specifies a filename that Mason will check once at the beginning of of every
request. When the file timestamp changes, Mason will (1) clear its in-memory
component cache, and (2) remove object files if they have not already been
deleted by another process.

This provides a convenient way to implement L</static_source> mode. All you
need to do is make sure that a single file gets touched whenever components
change. For Mason's part, checking a single file at the beginning of a request
is much cheaper than checking every component file when static_source=0.

=item top_level_extensions

Array reference of filename extensions for top-level components. Default is C<<
[".pm", ".m"] >>.

=back

=head1 REQUEST AND COMPILER PARAMETERS

Constructor parameters for Compiler and Request objects (Mason::Compiler and
Mason::Request by default) may be passed to the Interp constructor, and they
will be passed along whenever a compiler or request is created.

=head1 ACCESSOR METHODS

All of the above properties have standard read-only accessor methods of the
same name.

=head1 OTHER METHODS

=over

=item comp_exists (path)

Given an I<absolute> component path, this method returns a boolean value
indicating whether or not a component exists for that path.

=item run ([request params], path, args...)

Creates a new Mason::Request object for the given I<path> and I<args>, and
executes it. Request output is sent to the default L<Request/out_method>. The
return value is the return value of the request's top level component, if any.

The first argument may optionally be a hashref of request parameters, which are
passed to the Mason::Request constructor.

=item srun (path, args...)

Same as L</run>, but returns request output as a string (think sprintf versus
printf).

=item flush_code_cache

Empties the component cache. When using Perl 5.00503 or earlier, you should
call this when finished with an interpreter, in order to remove circular
references that would prevent the interpreter from being destroyed.

=item load (path)

Returns the component object corresponding to an absolute component I<path>, or
undef if none exists. Dies with an error if the component fails to load because
of a syntax error.

=back

=head1 SEE ALSO

L<Mason|Mason>

=cut
