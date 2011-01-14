package Mason::Interp;
use File::Basename;
use File::Temp qw(tempdir);
use Guard;
use JSON;
use List::Util qw(first);
use Mason::Compiler;
use Mason::Request;
use Mason::Result;
use Mason::Types;
use Mason::Util qw(catdir catfile mason_canon_path touch_file);
use Memoize;
use Moose::Util::TypeConstraints;
use Moose;
use Mason::Moose;
use MooseX::StrictConstructor;
use autodie qw(:all);
use strict;
use warnings;

my $default_out = sub { print( $_[0] ) };
my $interp_id = 0;

# Passed attributes
#
has 'autobase_names'           => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'comp_root'                => ( isa        => 'Mason::Types::CompRoot', coerce => 1 );
has 'compiler'                 => ( lazy_build => 1 );
has 'component_class_prefix'   => ( lazy_build => 1 );
has 'data_dir'                 => ( lazy_build => 1 );
has 'mason_root_class'         => ( required => 1 );
has 'object_file_extension'    => ( default => '.mobj' );
has 'plugins'                  => ( default => sub { [] } );
has 'static_source'            => ( );
has 'static_source_touch_file' => ( );

# Class overrides
#
my %class_overrides = (
    compilation_class             => 'Compilation',
    compiler_class                => 'Compiler',
    component_class               => 'Component',
    component_class_meta_class    => 'Component::ClassMeta',
    component_instance_meta_class => 'Component::InstanceMeta',
    request_class                 => 'Request',
    result_class                  => 'Result',
);
while ( my ( $method_name, $name ) = each(%class_overrides) ) {
    my $base_method_name   = "base_$method_name";
    my $default_base_class = "Mason::$name";
    has $method_name      => ( init_arg => undef, lazy_build => 1 );
    has $base_method_name => ( isa      => 'Str', default    => $default_base_class );
    __PACKAGE__->meta->add_method(
        "_build_$method_name" => sub {
            my $self = shift;
            return $self->mason_root_class->apply_plugins( $self->$base_method_name, $name,
                $self->plugins );
        }
    );
}

# Derived attributes
#
has 'autobase_regex'        => ( lazy_build => 1, init_arg => undef );
has 'code_cache'            => ( init_arg => undef );
has 'compiler_params'       => ( init_arg => undef );
has 'distinct_string_count' => ( init_arg => undef, default => 0 );
has 'id'                    => ( init_arg => undef );
has 'request_count'         => ( init_arg => undef, default => 0, reader => { request_count => sub { $_[0]->{request_count}++ } } );
has 'request_params'        => ( init_arg => undef );

#
# BUILD
#

method BUILD ($params) {
    $self->{code_cache} = {};
    $self->{id}         = $interp_id++;

    # Initialize static source mode
    #
    if ( $self->{static_source} ) {
        $self->{static_source_touch_file} ||= catfile( $self->data_dir, 'purge.dat' );
        $self->{static_source_touch_lastmod} = 0;
        $self->check_static_source_touch_file();
    }

    # Separate out compiler and request parameters
    #
    $self->{compiler_params} = {};
    my %is_compiler_attribute =
      map { ( $_->init_arg || $_->name, 1 ) } $self->compiler_class->meta->get_all_attributes();
    foreach my $key ( keys(%$params) ) {
        if ( $is_compiler_attribute{$key} ) {
            $self->{compiler_params}->{$key} = delete( $params->{$key} );
        }
    }
    $self->{request_params} = {};
    my %is_request_attribute =
      map { ( $_->init_arg || $_->name, 1 ) } $self->request_class->meta->get_all_attributes();
    foreach my $key ( keys(%$params) ) {
        if ( $is_request_attribute{$key} ) {
            $self->{request_params}->{$key} = delete( $params->{$key} );
        }
    }
}

method _build_autobase_names () {
    return [ "Base.pm", "Base.m" ];
}

method _build_autobase_regex () {
    my $regex = '(' . join( "|", @{ $self->autobase_names } ) . ')$';
    return qr/$regex/;
}

method _build_compiler () {
    return $self->compiler_class->new( interp => $self, %{ $self->compiler_params } );
}

method _build_component_class_prefix () {
    return "MC" . $self->{id};
}

method _build_data_dir () {
    return tempdir( 'mason-data-XXXX', TMPDIR => 1, CLEANUP => 1 );
}

#
# PUBLIC METHODS
#

method comp_exists ($path) {
    return $self->source_file_for_path( Mason::Util::mason_canon_path($path) );
}

method load ($path) {

    my $code_cache = $self->code_cache;

    # Canonicalize path
    #
    $path = Mason::Util::mason_canon_path($path);

    my $compile = 0;
    my (
        $default_parent_compc, $source_file, $source_lastmod, $object_file,
        $object_lastmod,       @source_stat, @object_stat
    );

    my $stat_source_file = sub {
        if ( $source_file = $self->source_file_for_path($path) ) {
            @source_stat = stat $source_file;
            if ( @source_stat && !-f _ ) {
                die "source file '$source_file' exists but it is not a file";
            }
        }
        $source_lastmod = @source_stat ? $source_stat[9] : 0;
    };

    my $stat_object_file = sub {
        $object_file = $self->object_file_for_path($path);
        @object_stat = stat $object_file;
        if ( @object_stat && !-f _ ) {
            die "object file '$object_file' exists but it is not a file";
        }
        $object_lastmod = @object_stat ? $object_stat[9] : 0;
    };

    if ( $self->static_source ) {

        # Check memory cache
        #
        if ( my $entry = $code_cache->{$path} ) {
            return $entry->{compc};
        }

        # Determine source and object files and their modified times
        #
        $stat_source_file->() or return;
        if ( $stat_object_file->() ) {

            # If touch file is more recent than object file, we can't trust object file.
            #
            if ( $self->{static_source_touch_lastmod} >= $object_lastmod ) {

                # If source file is more recent, recompile. Otherwise, touch
                # the object file so it will be trusted.
                #
                if ( $source_lastmod > $object_lastmod ) {
                    $compile = 1;
                }
                else {
                    touch_file($object_file);
                }
            }
        }
        else {
            $compile = 1;
        }

        # Determine default parent comp
        #
        $default_parent_compc = $self->default_parent_compc($path);
    }
    else {

        # Determine source file and its last modified time
        #
        $stat_source_file->() or return;

        # Determine default parent comp
        #
        $default_parent_compc = $self->default_parent_compc($path);

        # Check memory cache
        #
        if ( my $entry = $code_cache->{$path} ) {
            if (   $entry->{source_lastmod} >= $source_lastmod
                && $entry->{source_file} eq $source_file
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
        $stat_object_file->();
        $compile = ( !$object_lastmod || $object_lastmod < $source_lastmod );
    }

    $self->compiler->compile_to_file( $source_file, $path, $object_file ) if $compile;

    my $compc = $self->comp_class_for_path($path);

    $self->load_class_from_object_file( $compc, $object_file, $path, $default_parent_compc );

    # Save component class in the cache.
    #
    my $guard = guard { Mason::Util::delete_package($compc) };
    $code_cache->{$path} = {
        source_file          => $source_file,
        source_lastmod       => $source_lastmod,
        default_parent_compc => $default_parent_compc,
        compc                => $compc,
        guard                => $guard
    };

    return $compc;
}

# Memoize load() - this helps both with components used multiple times in a
# request, and with determining default parent components.  The memoize
# cache is cleared at the beginning of each request, or in
# static_source_mode, when the purge file is touched.
#
memoize('load');

method object_dir () {
    return catdir( $self->data_dir, 'obj' );
}

method run () {
    my %request_params;
    while ( ref( $_[0] ) eq 'HASH' ) {
        %request_params = ( %request_params, %{ shift(@_) } );
    }
    my $path = shift;
    my $request = $self->make_request( %request_params, request_params => \%request_params );
    $request->run( $path, @_ );
}

#
# PRIVATE METHODS
#

method add_default_render_method ($compc, $flags) {

    # Default render method for any component that doesn't define one.
    # Call inner() until we're back down at the page component ($self),
    # then call main().
    #
    unless ( $compc->meta->has_method('render') ) {
        my $path = $compc->cmeta->path;
        my $code = sub {
            my $self = shift;
            if ( $self->cmeta->path eq $path ) {
                $self->main(@_);
            }
            else {
                $compc->_inner();
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

method make_request () {
    return $self->request_class->new( interp => $self, %{ $self->request_params }, @_ );
}

method check_static_source_touch_file () {

    # Check the static_source_touch_file, if one exists, to see if it has
    # changed since we last checked. If it has, clear the code cache.
    #
    if ( my $touch_file = $self->static_source_touch_file ) {
        return unless -f $touch_file;
        my $touch_file_lastmod = ( stat($touch_file) )[9];
        if ( $touch_file_lastmod > $self->{static_source_touch_lastmod} ) {
            $self->flush_code_cache;
            $self->{static_source_touch_lastmod} = $touch_file_lastmod;
        }
    }
}

method flush_code_cache () {
    my $code_cache = $self->code_cache;

    # Try to dismantle code cache in a slightly orderly way before deleting
    # the cache. Packages will be deleted as each guard is removed.
    #
    foreach my $entry ( values %$code_cache ) {
        undef $entry->{guard};
    }
    $self->{code_cache} = {};
}

method comp_class_for_path ($path) {
    my $classname = substr( $path, 1 );
    $classname =~ s/[^\w]/_/g;
    $classname =~ s/\//::/g;
    $classname = join( "::", $self->component_class_prefix, $classname );
    return $classname;
}

method default_parent_compc ($path) {

    # Given /foo/bar.m, look for (by default):
    #   /foo/Base.pm, /foo/Base.m,
    #   /Base.pm, /Base.m
    #
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
            return $self->component_class;
        }
        $path = dirname($path);
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
            $parent_compc = $self->component_class;
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

method flush_load_cache () {
    Memoize::flush_cache('load');
}

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

    $compc->_set_class_cmeta($self);
    $self->add_default_render_method( $compc, $flags );
}

method construct_distinct_string () {
    my $number = ++$self->{distinct_string_count};
    my $str    = $self->construct_distinct_string_for_number($number);
    return $str;
}

method construct_distinct_string_for_number ($number) {
    my $distinct_delimeter = "__MASON__";
    return sprintf( "%s%d%s", $distinct_delimeter, $number, $distinct_delimeter );
}

method object_create_marker_file () {
    return catfile( $self->object_dir, '.__obj_create_marker' );
}

method object_file_for_path ($path) {
    return catfile( $self->object_dir, $self->compiler->compiler_id, ( split /\//, $path ), )
      . $self->object_file_extension;
}

method source_file_for_path ($path) {
    die "'$path' is not an absolute path" unless substr( $path, 0, 1 ) eq '/';
    foreach my $root_path ( @{ $self->comp_root } ) {
        my $source_file = $root_path . $path;
        return $source_file if -f $source_file;
    }
    return undef;
}

__PACKAGE__->meta->make_immutable();

1;

# ABSTRACT: Mason Interpreter
__END__

=head1 SYNOPSIS

    my $interp = Mason->new (comp_root => '/path/to/comps',
                             data_dir  => '/path/to/data',
                             ...);

    my $output = $interp->run('/request/path', foo => 5)->output();

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
F</products/sales.m> translates to the file
F</usr/local/httpd/docs/products/sales.m>.

This parameter may be either a single path or an array reference of paths. If
it is an array reference, the paths will be searched in the provided order
whenever a component path is resolved, much like Perl's C<< @INC >>.

=item compiler

The Compiler object to associate with this Interpreter.  By default a new
object of class L</compiler_class> will be created.

=item component_class_prefix

Prefix to use in generated component classnames. Defaults to 'MC' plus a unique
number for the interpreter, e.g. MC0. So a component '/foo/bar' would get a
classname like 'MC0::foo::bar'.

=item data_dir

The data directory is a writable directory that Mason uses for various features
and optimizations: for example, component object files and data cache files.
Mason will create the directory on startup if necessary.

Defaults to a temporary directory that will be cleaned up at process end. This
will hurt performance as Mason will have to recompile components on each run.

=item object_file_extension

Extension to add to the end of object files. Default is ".mobj".

=item static_source

True or false, default is false. When false, Mason checks the timestamp of the
component source file each time the component is used to see if it has changed.
This provides the instant feedback for source changes that is expected for
development.  However it does entail a file stat for each component executed.

When true, Mason assumes that the component source tree is unchanging: it will
not check component source files to determine if the memory cache or object
file has expired.  This can save many file stats per request. However, in order
to get Mason to recognize a component source change, you must touch the
L</static_source_touch_file>.

We recommend turning this mode on in your production sites if possible, if
performance is of any concern.

=item static_source_touch_file

Specifies a filename that Mason will check once at the beginning of every
request when in L</static_source> mode. When the file timestamp changes
(indicating that a component has changed), Mason will clear its in-memory
component cache and recheck existing object files.

=back

=head1 REQUEST AND COMPILER PARAMETERS

Constructor parameters for Compiler and Request objects (Mason::Compiler and
Mason::Request by default) may be passed to the Interp constructor, and they
will be passed along whenever a compiler or request is created.

=head1 CUSTOM MASON CLASSES

The Interp is responsible, directly or indirectly, for creating all other core
Mason objects. You can specify alternate classes to use instead of the default
Mason:: classes.

For example, to specify your own Compiler base class:

    my $interp = Mason->new(base_compiler_class => 'MyApp::Mason::Compiler', ...);

Relevant plugins, if any, will applied to this class to create a final class,
which you can get with

    $interp->compiler_class

=over

=item base_compilation_class

Specify alternate to L<Mason::Compiler|Mason::Compilation>

=item base_compiler_class

Specify alternate to L<Mason::Compiler|Mason::Compiler>

=item base_component_class

Specify alternate to L<Mason::Component|Mason::Component>

=item base_component_class_meta_class

Specify alternate to L<Mason::Component::ClassMeta|Mason::Component::ClassMeta>

=item base_component_instance_meta_class

Specify alternate to
L<Mason::Component::IntanceMeta|Mason::Component::IntanceMeta>

=item base_request_class

Specify alternate to L<Mason::Request|Mason::Request>

=item base_result_class

Specify alternate to L<Mason::Result|Mason::Result>

=back

=head1 THE RUN METHOD

=over

=item run ([request params], path, args...)

Creates a new L<Mason::Request|Mason::Request> object for the given I<path> and
I<args>, and executes it. Returns a L<Mason::Result|Mason::Result> object,
which is generally accessed to get the output. e.g.

    my $output = $interp->run('/foo/bar', baz => 5)->output;

The first argument may optionally be a hashref of request parameters, which are
passed to the Mason::Request constructor. e.g. this tells the request to output
to standard output:

    $interp->run({out_method => sub { print $_[0] }}, '/foo/bar', baz => 5);

=back

=head1 ACCESSOR METHODS

All of the above properties have standard read-only accessor methods of the
same name.

=head1 OTHER METHODS

=over

=item comp_exists (path)

Given an I<absolute> component path, this method returns a boolean value
indicating whether or not a component exists for that path.

=item flush_code_cache

Empties the component cache. When using Perl 5.00503 or earlier, you should
call this when finished with an interpreter, in order to remove circular
references that would prevent the interpreter from being destroyed.

=item load (path)

Returns the component object corresponding to an absolute component I<path>, or
undef if none exists. Dies with an error if the component fails to load because
of a syntax error.

=back

=cut
