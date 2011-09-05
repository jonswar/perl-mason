package Mason::Interp;
use Carp;
use Devel::GlobalDestruction;
use File::Basename;
use File::Path;
use File::Temp qw(tempdir);
use Guard;
use Mason::CodeCache;
use Mason::Request;
use Mason::Result;
use Mason::Types;
use Mason::Util
  qw(can_load catdir catfile combine_similar_paths find_wanted first_index is_absolute json_decode mason_canon_path read_file taint_is_on touch_file uniq write_file);
use Memoize;
use Moose::Util::TypeConstraints;
use Mason::Moose;

my $default_out = sub { print( $_[0] ) };
my $next_id     = 0;
my $max_depth   = 16;

# Passed attributes
#
has 'allow_globals'            => ( isa => 'ArrayRef[Str]', default => sub { [] }, trigger => sub { shift->_validate_allow_globals } );
has 'autobase_names'           => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'autoextend_request_path'  => ( isa => 'Bool', default => 1 );
has 'comp_root'                => ( required => 1, isa => 'Mason::Types::CompRoot', coerce => 1 );
has 'component_class_prefix'   => ( lazy_build => 1 );
has 'data_dir'                 => ( lazy_build => 1 );
has 'dhandler_names'           => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'index_names'              => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'mason_root_class'         => ( required => 1 );
has 'no_source_line_numbers'   => ( default => 0 );
has 'object_file_extension'    => ( default => '.mobj' );
has 'plugins'                  => ( default => sub { [] } );
has 'pure_perl_extensions'     => ( default => sub { ['.mp'] } );
has 'static_source'            => ();
has 'static_source_touch_file' => ();
has 'top_level_extensions'     => ( default => sub { ['.mc', '.mp'] } );

# Derived attributes
#
has 'allowed_globals_hash'  => ( init_arg => undef, lazy_build => 1 );
has 'code_cache'            => ( init_arg => undef, lazy_build => 1 );
has 'distinct_string_count' => ( init_arg => undef, default => 0 );
has 'globals_package'       => ( init_arg => undef, lazy_build => 1 );
has 'id'                    => ( init_arg => undef, default => sub { $next_id++ } );
has 'match_request_path'    => ( init_arg => undef, lazy_build => 1 );
has 'pure_perl_regex'       => ( lazy_build => 1 );
has 'request_params'        => ( init_arg => undef );
has 'top_level_regex'       => ( lazy_build => 1 );

# Class overrides
#
CLASS->_define_class_override_methods();

# Allow access to current interp while in load()
#
our ($current_load_interp);
method current_load_interp () { $current_load_interp }

#
# BUILD
#

method BUILD ($params) {

    # Initialize static source mode
    #
    if ( $self->{static_source} ) {
        $self->{static_source_touch_file} ||= catfile( $self->data_dir, 'purge.dat' );
        $self->{static_source_touch_lastmod} = 0;
        $self->_check_static_source_touch_file();
    }

    # Separate out request parameters
    #
    $self->{request_params} = {};
    my %is_request_attribute =
      map { ( $_->init_arg || $_->name, 1 ) } $self->request_class->meta->get_all_attributes();
    foreach my $key ( keys(%$params) ) {
        if ( $is_request_attribute{$key} ) {
            $self->{request_params}->{$key} = delete( $params->{$key} );
        }
    }
}

method _build_allowed_globals_hash () {
    my @allow_globals = uniq( @{ $self->allow_globals } );
    my @canon_globals = map { join( "", $self->_parse_global_spec($_) ) } @allow_globals;
    return { map { ( $_, 1 ) } @canon_globals };
}

method _build_globals_package () {
    return "Mason::Globals" . $self->id;
}

method _build_autobase_names () {
    return [ map { "Base" . $_ } @{ $self->top_level_extensions } ];
}

method _build_code_cache () {
    return $self->code_cache_class->new();
}

method _build_component_class_prefix () {
    return "MC" . $self->id;
}

method _build_data_dir () {
    return tempdir( 'mason-data-XXXX', TMPDIR => 1, CLEANUP => 1 );
}

method _build_dhandler_names () {
    return [ map { "dhandler" . $_ } @{ $self->top_level_extensions } ];
}

method _build_index_names () {
    return [ map { "index" . $_ } @{ $self->top_level_extensions } ];
}

method _build_pure_perl_regex () {
    my $extensions = $self->pure_perl_extensions;
    if ( !@$extensions ) {
        return qr/(?!)/;                  # matches nothing
    }
    else {
        my $regex = join( '|', @$extensions ) . '$';
        return qr/$regex/;
    }
}

method _build_top_level_regex () {
    my $extensions = $self->top_level_extensions;
    if ( !@$extensions ) {
        return qr/./;                     # matches everything
    }
    else {
        my $regex = join( '|', @$extensions );
        if ( my @other_names = grep { !/$regex/ } @{ $self->dhandler_names },
            @{ $self->index_names } )
        {
            $regex .= '|(?:/(?:' . join( '|', @other_names ) . '))';
        }
        $regex = '(?:' . $regex . ')$';
        return qr/$regex/;
    }
}

#
# PUBLIC METHODS
#

method all_paths ($dir_path) {
    $dir_path ||= '/';
    $self->_assert_absolute_path($dir_path);
    return $self->_collect_paths_for_all_comp_roots(
        sub {
            my $root_path = shift;
            my $dir       = $root_path . $dir_path;
            return ( -d $dir ) ? find_wanted( sub { -f }, $dir ) : ();
        }
    );
}

method comp_exists ($path) {

    # Canonicalize path
    #
    croak "path required" if !defined($path);
    $path = Mason::Util::mason_canon_path($path);

    return ( ( $self->static_source && $self->code_cache->get($path) )
          || $self->_source_file_for_path($path) ) ? 1 : 0;
}

method flush_code_cache () {
    my $code_cache = $self->code_cache;

    foreach my $key ( $code_cache->get_keys() ) {
        $code_cache->remove($key);
    }
}

method glob_paths ($glob_pattern) {
    return $self->_collect_paths_for_all_comp_roots(
        sub {
            my $root_path = shift;
            return glob( $root_path . $glob_pattern );
        }
    );
}

our $in_load = 0;

method load ($path) {

    local $current_load_interp = $self;

    my $code_cache = $self->code_cache;

    # Canonicalize path
    #
    croak "path required" if !defined($path);
    $path = Mason::Util::mason_canon_path($path);

    # Quick check memory cache in static source mode
    #
    if ( $self->static_source ) {
        if ( my $entry = $code_cache->get($path) ) {
            return $entry->{compc};
        }
    }

    local $in_load = $in_load + 1;
    if ( $in_load > $max_depth ) {
        die ">$max_depth levels deep in inheritance determination (inheritance cycle?)"
          if $in_load >= $max_depth;
    }

    my $compile = 0;
    my (
        $default_parent_path, $source_file, $source_lastmod, $object_file,
        $object_lastmod,      @source_stat, @object_stat
    );

    my $stat_source_file = sub {
        if ( $source_file = $self->_source_file_for_path($path) ) {
            @source_stat = stat $source_file;
            if ( @source_stat && !-f _ ) {
                die "source file '$source_file' exists but it is not a file";
            }
        }
        $source_lastmod = @source_stat ? $source_stat[9] : 0;
    };

    my $stat_object_file = sub {
        $object_file = $self->_object_file_for_path($path);
        @object_stat = stat $object_file;
        if ( @object_stat && !-f _ ) {
            die "object file '$object_file' exists but it is not a file";
        }
        $object_lastmod = @object_stat ? $object_stat[9] : 0;
    };

    # Determine source and object files and their modified times
    #
    $stat_source_file->() or return;

    # Determine default parent comp
    #
    $default_parent_path = $self->_default_parent_path($path);

    if ( $self->static_source ) {

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

    }
    else {

        # Check memory cache
        #
        if ( my $entry = $code_cache->get($path) ) {
            if (   $entry->{source_lastmod} >= $source_lastmod
                && $entry->{source_file} eq $source_file
                && $entry->{default_parent_path} eq $default_parent_path )
            {
                my $compc = $entry->{compc};
                if ( $entry->{superclass_signature} eq $self->_superclass_signature($compc) ) {
                    return $compc;
                }
            }
            $code_cache->remove($path);
        }

        # Determine object file and its last modified time
        #
        $stat_object_file->();
        $compile = ( !$object_lastmod || $object_lastmod < $source_lastmod );
    }

    $self->_compile_to_file( $source_file, $path, $object_file ) if $compile;

    my $compc = $self->_comp_class_for_path($path);

    $self->_load_class_from_object_file( $compc, $object_file, $path, $default_parent_path );
    $compc->meta->make_immutable();

    # Save component class in the cache.
    #
    $code_cache->set(
        $path,
        {
            source_file          => $source_file,
            source_lastmod       => $source_lastmod,
            default_parent_path  => $default_parent_path,
            compc                => $compc,
            superclass_signature => $self->_superclass_signature($compc),
        }
    );

    return $compc;
}

method _superclass_signature ($compc) {
    my @superclasses = $compc->meta->superclasses;

    # Recursively load the superclasses for an existing component class in
    # case they have changed.
    #
    foreach my $superclass (@superclasses) {
        if ( my $cmeta = $superclass->cmeta ) {
            my $path = $cmeta->path;
            $self->load( $cmeta->path );
        }
    }

    # Return a unique signature representing the component class's superclasses
    # and their versions.
    #
    return join( ",", map { join( "-", $_, $_->cmeta ? $_->cmeta->id : 0 ) } @superclasses );
}

# Memoize comp_exists() and load() - this helps both with components used
# multiple times in a request, and with determining default parent
# components.  The memoize cache is cleared at the beginning of each
# request, or in static_source_mode, when the purge file is touched.
#
memoize('comp_exists');
memoize('load');

method object_dir () {
    return catdir( $self->data_dir, 'obj' );
}

method run () {
    my %request_params;
    if ( ref( $_[0] ) eq 'HASH' ) {
        %request_params = %{ shift(@_) };
    }
    my $path    = shift;
    my $request = $self->_make_request(%request_params);
    $request->run( $path, @_ );
}

method set_global () {
    my ( $spec, $value ) = @_;
    croak "set_global expects a var name and value" unless $value;
    my ( $sigil, $name ) = $self->_parse_global_spec($spec);
    croak "${sigil}${name} is not in the allowed globals list"
      unless $self->allowed_globals_hash->{"${sigil}${name}"};

    my $varname = sprintf( "%s::%s", $self->globals_package, $name );
    no strict 'refs';
    no warnings 'once';
    $$varname = $value;
}

#
# MODIFIABLE METHODS
#

method DEMOLISH () {
    return if in_global_destruction;

    # We have to check for code_cache slot directly, in case the object gets
    # destroyed before it has been fully formed (e.g. missing required attr).
    #
    $self->flush_code_cache() if defined( $self->{code_cache} );
}

method _compile ( $source_file, $path ) {
    my $compilation = $self->compilation_class->new(
        source_file => $source_file,
        path        => $path,
        interp      => $self
    );
    return $compilation->compile();
}

method _compile_to_file ( $source_file, $path, $object_file ) {

    # We attempt to handle several cases in which a file already exists
    # and we wish to create a directory, or vice versa.  However, not
    # every case is handled; to be complete, mkpath would have to unlink
    # any existing file in its way.
    #
    if ( defined $object_file && !-f $object_file ) {
        my ($dirname) = dirname($object_file);
        if ( !-d $dirname ) {
            unlink($dirname) if ( -e _ );
            mkpath( $dirname, 0, 0775 );
        }
        rmtree($object_file) if ( -d $object_file );
    }
    my $object_contents = $self->_compile( $source_file, $path );

    $self->write_object_file( $object_file, $object_contents );
}

method is_pure_perl_comp_path ($path) {
    return ( $path =~ $self->pure_perl_regex ) ? 1 : 0;
}

method is_top_level_comp_path ($path) {
    return ( $path =~ $self->top_level_regex ) ? 1 : 0;
}

method _load_class_from_object_file ( $compc, $object_file, $path, $default_parent_path ) {
    my $flags = $self->_extract_flags_from_object_file($object_file);
    my $parent_compc =
         $self->_determine_parent_compc( $path, $flags )
      || ( $default_parent_path eq '/' && $self->component_class )
      || $self->load($default_parent_path);

    my $code = sprintf( 'package %s; use Moose; extends "%s"; do("%s"); die $@ if $@',
        $compc, $parent_compc, $object_file );
    ($code) = ( $code =~ /^(.*)/s ) if taint_is_on();
    eval($code);
    die $@ if $@;

    $compc->_set_class_cmeta($self);
    $self->modify_loaded_class($compc);
}

method modify_loaded_class ($compc) {
    $self->_add_default_wrap_method($compc);
}

method write_object_file ($object_file, $object_contents) {
    write_file( $object_file, $object_contents );
}

# Given /foo/bar, look for (by default):
#   /foo/bar/index.{mp,mc},
#   /foo/bar/dhandler.{mp,mc},
#   /foo/bar.{mp,mc},
#   /dhandler.{mp,mc},
#   /foo.{mp,mc}
#
method _build_match_request_path ($interp:) {

    # Create a closure for efficiency - all this data is immutable for an interp.
    #
    my @dhandler_subpaths = map { "/$_" } @{ $interp->dhandler_names };
    my $ignore_file_regex =
      '(/' . join( "|", @{ $interp->autobase_names }, @{ $interp->dhandler_names } ) . ')$';
    $ignore_file_regex = qr/$ignore_file_regex/;
    my %is_dhandler_name = map { ( $_, 1 ) } @{ $interp->dhandler_names };
    my @autoextensions = $interp->autoextend_request_path ? @{ $interp->top_level_extensions } : ();
    my @index_names = @{ $interp->index_names };
    undef $interp;    # So this doesn't end up in closure and cause cycle

    return sub {
        my ( $request, $request_path ) = @_;
        my $interp         = $request->interp;
        my $path_info      = '';
        my $declined_paths = $request->declined_paths;
        my @index_subpaths = map { "/$_" } @index_names;
        my $path           = $request_path;
        my @tried_paths;

        while (1) {
            my @candidate_paths =
                ( $path_info eq '' && !@autoextensions ) ? ($path)
              : ( $path eq '/' ) ? ( @index_subpaths, @dhandler_subpaths )
              : (
                ( grep { !/$ignore_file_regex/ } map { $path . $_ } @autoextensions ),
                ( map { $path . $_ } ( @index_subpaths, @dhandler_subpaths ) )
              );
            push( @tried_paths, @candidate_paths );
            foreach my $candidate_path (@candidate_paths) {
                next if $declined_paths->{$candidate_path};
                if ( my $compc = $interp->load($candidate_path) ) {
                    if (
                        $compc->cmeta->is_top_level
                        && (   $path_info eq ''
                            || $compc->cmeta->is_dhandler
                            || $compc->allow_path_info )
                      )
                    {
                        $request->{path_info} = $path_info;
                        return $compc->cmeta->path;
                    }
                }
            }
            $interp->_top_level_not_found( $request_path, \@tried_paths ) if $path eq '/';
            my $name = basename($path);
            $path_info = length($path_info) ? "$name/$path_info" : $name;
            $path = dirname($path);
            @index_subpaths = ();    # only match index file in same directory
        }
    };
}

#
# PRIVATE METHODS
#

method _parse_global_spec () {
    my $spec = shift;
    croak "only scalar globals supported at this time (not '$spec')" if $spec =~ /^[@%]/;
    $spec =~ s/^\$//;
    die "'$spec' is not a valid global var name" unless $spec =~ qr/^[[:alpha:]_]\w*$/;
    return ( '$', $spec );
}

method _add_default_wrap_method ($compc) {

    # Default wrap method for any component that doesn't define one.
    # Call inner() until we're back down at the page component ($self),
    # then call main().
    #
    unless ( $compc->meta->has_method('wrap') ) {
        my $path = $compc->cmeta->path;
        my $code = sub {
            my $self = shift;
            if ( $self->cmeta->path eq $path ) {
                if ( $self->can('main') ) {
                    $self->main(@_);
                }
                else {
                    die sprintf(
                        "component '%s' ('%s') was called but has no main method - did you forget to define 'main' or 'handle'?",
                        $path, $compc->cmeta->source_file );
                }
            }
            else {
                $compc->_inner();
            }
        };
        $compc->meta->add_augment_method_modifier( wrap => $code );
    }
}

method _assert_absolute_path ($path) {
    $path ||= '';
    croak "'$path' is not an absolute path" unless is_absolute($path);
}

method _check_static_source_touch_file () {

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

method _collect_paths_for_all_comp_roots ($code) {
    my @paths;
    foreach my $root_path ( @{ $self->comp_root } ) {
        my $root_path_length = length($root_path);
        my @files            = $code->($root_path);
        push( @paths, map { substr( $_, $root_path_length ) } @files );
    }
    return uniq(@paths);
}

method _comp_class_for_path ($path) {
    my $classname = substr( $path, 1 );
    $classname =~ s/[^\w]/_/g;
    $classname =~ s/\//::/g;
    $classname = join( "::", $self->component_class_prefix, $classname );
    return $classname;
}

method _construct_distinct_string () {
    my $number = ++$self->{distinct_string_count};
    my $str    = $self->_construct_distinct_string_for_number($number);
    return $str;
}

method _construct_distinct_string_for_number ($number) {
    my $distinct_delimeter = "__MASON__";
    return sprintf( "%s%d%s", $distinct_delimeter, $number, $distinct_delimeter );
}

method _default_parent_path ($orig_path) {

    # Given /foo/bar.mc, look for (by default):
    #   /foo/Base.mp, /foo/Base.mc,
    #   /Base.mp, /Base.mc
    #
    # Split path into dir_path and base_name - validate that it has a
    # starting slash and ends with at least one non-slash character
    #
    my ( $dir_path, $base_name ) = ( $orig_path =~ m{^(/.*?)/?([^/]+)$} )
      or die "not a valid absolute component path - '$orig_path'";
    my $path = $dir_path;

    my @autobase_subpaths = map { "/$_" } @{ $self->autobase_names };
    while (1) {
        my @candidate_paths =
          ( $path eq '/' )
          ? @autobase_subpaths
          : ( map { $path . $_ } @autobase_subpaths );
        if ( ( my $index = first_index { $_ eq $orig_path } @candidate_paths ) != -1 ) {
            splice( @candidate_paths, 0, $index + 1 );
        }
        foreach my $candidate_path (@candidate_paths) {
            if ( $self->comp_exists($candidate_path) ) {
                return $candidate_path;
            }
        }
        if ( $path eq '/' ) {
            return '/';
        }
        $path = dirname($path);
    }
}

method _determine_parent_compc ($path, $flags) {
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

method _extract_flags_from_object_file ($object_file) {
    my $flags = {};
    open( my $fh, "<", $object_file ) or die "could not open '$object_file': $!";
    my $line = <$fh>;
    if ( my ($flags_str) = ( $line =~ /\# FLAGS: (.*)/ ) ) {
        $flags = json_decode($flags_str);
    }
    return $flags;
}

method _flush_load_cache () {
    Memoize::flush_cache('comp_exists');
    Memoize::flush_cache('load');
}

method _make_request () {
    return $self->request_class->new( interp => $self, %{ $self->request_params }, @_ );
}

method _object_file_for_path ($path) {
    return catfile( $self->object_dir, ( split /\//, $path ) ) . $self->object_file_extension;
}

method _source_file_for_path ($path) {
    $self->_assert_absolute_path($path);
    foreach my $root_path ( @{ $self->comp_root } ) {
        my $source_file = $root_path . $path;
        return $source_file if -f $source_file;
    }
    return undef;
}

method _top_level_not_found ($path, $tried_paths) {
    my @combined_paths = combine_similar_paths(@$tried_paths);
    Mason::Exception::TopLevelNotFound->throw(
        error => sprintf(
            "could not resolve request path '%s'; searched for components (%s) under %s\n",
            $path,
            join( ", ", map { "'$_'" } @combined_paths ),
            @{ $self->comp_root } > 1
            ? "component roots " . join( ", ", map { "'$_'" } @{ $self->comp_root } )
            : "component root '" . $self->comp_root->[0] . "'"
        )
    );
}

method _validate_allow_globals () {

    # Will build allowed_globals_hash and also validate the param
    #
    $self->allowed_globals_hash;
}

#
# Class overrides. Put here at the bottom because it strangely messes up
# Perl line numbering if at the top.
#
sub _define_class_override_methods {
    my %class_overrides = (
        code_cache_class           => 'CodeCache',
        compilation_class          => 'Compilation',
        component_class            => 'Component',
        component_class_meta_class => 'Component::ClassMeta',
        component_import_class     => 'Component::Import',
        component_moose_class      => 'Component::Moose',
        request_class              => 'Request',
        result_class               => 'Result',
    );

    # e.g.
    # $method_name        = component_moose_class
    # $base_method_name   = base_component_moose_class
    # $name               = Component::Moose
    # $default_base_class = Mason::Component::Moose
    #
    while ( my ( $method_name, $name ) = each(%class_overrides) ) {
        my $base_method_name = "base_$method_name";
        has $method_name      => ( init_arg => undef, lazy_build => 1 );
        has $base_method_name => ( isa      => 'Str', lazy_build => 1 );
        __PACKAGE__->meta->add_method(
            "_build_$method_name" => sub {
                my $self       = shift;
                my $base_class = $self->$base_method_name;
                Class::MOP::load_class($base_class);
                return Mason::PluginManager->apply_plugins_to_class( $base_class, $name,
                    $self->plugins );
            }
        );
        __PACKAGE__->meta->add_method(
            "_build_$base_method_name" => sub {
                my $self = shift;
                my @candidates =
                  map { join( '::', $_, $name ) } ( uniq( $self->mason_root_class, 'Mason' ) );
                my ($base_class) = grep { can_load($_) } @candidates
                  or die
                  sprintf( "cannot load %s for %s", join( ', ', @candidates ), $base_method_name );
                return $base_class;
            }
        );
    }
}

__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

Mason::Interp - Mason Interpreter

=head1 SYNOPSIS

    my $interp = Mason->new(
        comp_root => '/path/to/comps',
        data_dir  => '/path/to/data',
        ...
    );
    my $output = $interp->run( '/request/path', foo => 5 )->output();

=head1 DESCRIPTION

Interp is the central Mason object, returned from C<< Mason->new >>. It is
responsible for creating new requests, compiling components, and maintaining
the cache of loaded components.

=head1 PARAMETERS TO THE new() CONSTRUCTOR

=for html <a name="allow_globals" />

=over

=item allow_globals (varnames)

List of one or more global variable names that will be available in all
components, like C<< $m >> is by default.

    allow_globals => [qw($dbh)]

As in any programming environment, globals should be created sparingly (if at
all) and only when other mechanisms (parameter passing, attributes, singletons)
will not suffice. L<Catalyst::View::Mason2|Catalyst::View::Mason2>, for
example, creates a C<< $c >> global set to the context object in each request.

Set the values of globals with L<set_global|/set_global>.

=for html <a name="autobase_names" />

=item autobase_names

Array reference of L<autobase|Mason::Manual/Autobase components> filenames to
check in order when determining a component's superclass. Default is C<<
["Base.mp", "Base.mc"] >>.

=for html <a name="autoextend_request_path" />

=item autoextend_request_path

Whether to automatically add the L<top level extensions|/top_level_extensions>
(by default ".mp" and ".mc") to the request path when searching for a matching
page component. Defaults to true.

=for html <a name="comp_root" />

=item comp_root

Required. The component root marks the top of your component hierarchy and
defines how component paths are translated into real file paths. For example,
if your component root is F</usr/local/httpd/docs>, a component path of
F</products/sales.mc> translates to the file
F</usr/local/httpd/docs/products/sales.mc>.

This parameter may be either a single path or an array reference of paths. If
it is an array reference, the paths will be searched in the provided order
whenever a component path is resolved, much like Perl's C<< @INC >>.

=for html <a name="component_class_prefix" />

=item component_class_prefix

Prefix to use in generated component classnames. Defaults to 'MC' plus the
interpreter's count, e.g. MC0. So a component '/foo/bar' would get a classname
like 'MC0::foo::bar'.

=for html <a name="data_dir" />

=item data_dir

The data directory is a writable directory that Mason uses for various features
and optimizations: for example, component object files and data cache files.
Mason will create the directory on startup if necessary.

Defaults to a temporary directory that will be cleaned up at process end. This
will hurt performance as Mason will have to recompile components on each run.

=for html <a name="dhandler_names" />

=item dhandler_names

Array reference of dhandler file names to check in order when resolving a
top-level path. Default is C<< ["dhandler.mp", "dhandler.mc"] >>. An empty list
disables this feature.

=for html <a name="index_names" />

=item index_names

Array reference of index file names to check in order when resolving a
top-level path. Default is C<< ["index.mp", "index.mc"] >>. An empty list
disables this feature.

=for html <a name="no_source_line_numbers" />

=item no_source_line_numbers

Do not put in source line number comments when generating code.  Setting this
to true will cause error line numbers to reflect the real object file, rather
than the source component.

=for html <a name="object_file_extension" />

=item object_file_extension

Extension to add to the end of object files. Default is ".mobj".

=for html <a name="plugins" />

=item plugins

A list of plugins and/or plugin bundles:

    plugins => [
      'OnePlugin', 
      'AnotherPlugin',
      '+My::Mason::Plugin::AThirdPlugin',
      '@APluginBundle',
      '-DontLikeThisPlugin',
    ]);

See L<Mason::Manual::Plugins>.

=for html <a name="out_method" />

=item out_method

Default L<out_method|Request/out_method> passed to each new request.

=for html <a name="pure_perl_extensions" />

=item pure_perl_extensions

A listref of file extensions of components to be considered as pure perl (see
L<Pure Perl Components|Mason::Manual::Syntax/Pure_Perl_Components>). Default is
C<< ['.mp'] >>. If an empty list is specified, then no components will be
considered pure perl.

=for html <a name="static_source" />

=item static_source

True or false, default is false. When false, Mason checks the timestamp of the
component source file each time the component is used to see if it has changed.
This provides the instant feedback for source changes that is expected for
development.  However it does entail a file stat for each component executed.

When true, Mason assumes that the component source tree is unchanging: it will
not check component source files to determine if the memory cache or object
file has expired.  This can save many file stats per request. However, in order
to get Mason to recognize a component source change, you must touch the
L<static_source_touch_file|/static_source_touch_file>.

We recommend turning this mode on in your production sites if possible, if
performance is of any concern.

=for html <a name="static_source_touch_file" />

=item static_source_touch_file

Specifies a filename that Mason will check once at the beginning of every
request when in L<static_source|/static_source> mode. When the file timestamp
changes (indicating that a component has changed), Mason will clear its
in-memory component cache and recheck existing object files.

=for html <a name="top_level_extensions" />

=item top_level_extensions

A listref of file extensions of components to be considered "top level",
accessible directly from C<< $interp->run >> or a web request. Default is C<<
['.mp', '.mc'] >>. If an empty list is specified, then there will be I<no>
restriction; that is, I<all> components will be considered top level.

=back

=head1 CUSTOM MASON CLASSES

These parameters specify alternate classes to use instead of the default
Mason:: classes.

For example, to use your own Compilation base class:

    my $interp = Mason->new(base_compilation_class => 'MyApp::Mason::Compilation', ...);

L<Relevant plugins|Mason::Manual::Plugins>, if any, will applied to this class
to create a final class, which you can get with

    $interp->compilation_class

=for html <a name="base_code_cache_class" />

=over

=item base_code_cache_class

Specify alternate to L<Mason::CodeCache|Mason::CodeCache>

=for html <a name="base_compilation_class" />

=item base_compilation_class

Specify alternate to L<Mason::Compilation|Mason::Compilation>

=for html <a name="base_component_class" />

=item base_component_class

Specify alternate to L<Mason::Component|Mason::Component>

=for html <a name="base_component_moose_class" />

=item base_component_moose_class

Specify alternate to L<Mason::Component::Moose|Mason::Component::Moose>

=for html <a name="base_component_class_meta_class" />

=item base_component_class_meta_class

Specify alternate to L<Mason::Component::ClassMeta|Mason::Component::ClassMeta>

=for html <a name="base_component_import_class" />

=item base_component_import_class

Specify alternate to L<Mason::Component::Import|Mason::Component::Import>

=for html <a name="base_request_class" />

=item base_request_class

Specify alternate to L<Mason::Request|Mason::Request>

=for html <a name="base_result_class" />

=item base_result_class

Specify alternate to L<Mason::Result|Mason::Result>

=back

=head1 PUBLIC METHODS

=for html <a name="all_paths" />

=over

=item all_paths ([dir_path])

Returns a list of distinct component paths under I<dir_path>, which defaults to
'/' if not provided.  For example,

   $interp->all_paths('/foo/bar')
      => ('/foo/bar/baz.mc', '/foo/bar/blargh.mc')

Note that these are all component paths, not filenames, and all component roots
are searched if there are multiple ones.

=for html <a name="comp_exists" />

=item comp_exists (path)

Returns a boolean indicating whether a component exists for the absolute
component I<path>.

=for html <a name="count" />

=item count

Returns the number of this interpreter, a monotonically increasing integer for
the process starting at 0.

=for html <a name="flush_code_cache" />

=item flush_code_cache

Empties the component cache and removes all component classes.

=for html <a name="glob_paths" />

=item glob_paths (pattern)

Returns a list of all component paths matching the glob I<pattern>. e.g.

   $interp->glob_paths('/foo/b*.mc')
      => ('/foo/bar.mc', '/foo/baz.mc')

Note that these are all component paths, not filenames, and all component roots
are searched if there are multiple ones.

=for html <a name="load" />

=item load (path)

Returns the component object corresponding to an absolute component I<path>, or
undef if none exists. Dies with an error if the component fails to load because
of a syntax error.

=for html <a name="object_dir" />

=item object_dir

Returns the directory containing component object files.

=for html <a name="run" />

=item run ([request params], path, args...)

Creates a new L<Mason::Request|Mason::Request> object for the given I<path> and
I<args>, and executes it. Returns a L<Mason::Result|Mason::Result> object,
which is generally accessed to get the output. e.g.

    my $output = $interp->run('/foo/bar', baz => 5)->output;

The first argument may optionally be a hashref of request parameters, which are
passed to the Mason::Request constructor. e.g. this tells the request to output
to standard output:

    $interp->run({out_method => sub { print $_[0] }}, '/foo/bar', baz => 5);

=for html <a name="set_global" />

=item set_global (varname, value)

Set the global I<varname> to I<value>. This will be visible in all components
loaded by this interpreter. The variables must be on the
L<allow_globals|/allow_globals> list.

    $interp->set_global('$scalar', 5);
    $interp->set_global('$scalar2', $some_object);

See also L<set_global|Mason::Request/set_global>.

=back

=head1 MODIFIABLE METHODS

These methods are not intended to be called externally, but may be useful to
modify with method modifiers in plugins and subclasses. We will attempt to keep
their APIs stable.

=for html <a name="is_pure_perl_comp_path" />

=over

=item is_pure_perl_comp_path ($path)

Determines whether I<$path> is a pure Perl component - by default, uses
L<pure_perl_extensions|/pure_perl_extensions>.

=for html <a name="is_top_level_comp_path" />

=item is_top_level_comp_path ($path)

Determines whether I<$path> is a valid top-level component - by default, uses
L<top_level_extensions|/top_level_extensions>.

=for html <a name="modify_loaded_class" />

=item modify_loaded_class ( $compc )

An opportunity to modify loaded component class I<$compc> (e.g. add additional
methods or apply roles) before it is made immutable.

=for html <a name="write_object_file" />

=item write_object_file ($object_file, $object_contents)

Write compiled component I<$object_contents> to I<$object_file>. This is an
opportunity to modify I<$object_contents> before it is written, or
I<$object_file> after it is written.

=back

=cut
