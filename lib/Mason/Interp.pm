package Mason::Interp;
use autodie qw(:all);
use Moose;
use strict;
use warnings;

subtype 'Mason::Types::CompRoot' => as 'ArrayRef' => where {
    ref($_) eq 'ARRAY' && all { ref($_) eq 'ARRAY' && @$_ == 2 } @$_;
};
coerce 'Mason::Types::CompRoot' => from 'Str' => via { [ 'MAIN', $_ ] };

has 'autohandler_name' => ( default => 'autohandler' );
has 'comp_root'        => ( isa     => 'Mason::Types::CompRoot' );
has 'compiler'         => ();
has 'chi_root_class'   => ();
has 'data_dir'         => ();
has 'dhandler_name'    => ();
has 'max_recurse'      => ();
has 'resolver'         => ();
has 'static_source'    => ();
has 'static_source_touch_file' => ();

__PACKAGE__->meta->make_immutable();

sub BUILD {
    my ($self) = @_;

    $self->{code_cache} = {};

    if ( $self->{static_source} ) {
        $self->{static_source_touch_file_lastmod} = 0;
        $self->{static_source_touch_file} ||=
          catfile( $self->data_dir, 'purge.dat' );
        $self->{use_internal_component_caches} = 1;
    }

    $self->_initialize_comp_root( $self->{comp_root} );
}

sub exec {
    my $self = shift;
    my $comp = shift;
    $self->make_request->exec( $comp, @_ );
}

sub make_request {
    my ($self) = @_;

    return $self->request_class->new( interp => $interp );
}

sub load {
    my ( $self, $path ) = @_;

    # Path must be absolute.
    #
    unless ( substr( $path, 0, 1 ) eq '/' ) {
        error
          "Component path given to Interp->load must be absolute (was given $path)";
    }

    # Get source info from resolver; return if cannot be found.
    #
    my $source = $self->resolve_comp_path_to_source($path)
      or return;
    my $srcmod = $source->last_modified;

    # comp_id is the unique name for the component, used for cache key
    # and object file name.
    #
    my $comp_id = $source->comp_id;

    # If code cache contains an entry for this path, and it is up to date
    # or we are in static_source_mode, return the cached comp.
    #
    my $code_cache = $self->{code_cache};
    if (
        exists $code_cache->{$comp_id}
        && (   $self->static_source
            || $code_cache->{$comp_id}->{lastmod} >= $srcmod )
      )
    {
        return $code_cache->{$comp_id}->{comp_class};
    }

    # Determine object file and its last modified time
    #
    my $objfile = $self->comp_id_to_objfile($comp_id);
    my @stat    = stat $objfile;
    if ( @stat && !-f _ ) {
        error "The object file '$objfile' exists but it is not a file!";
    }
    my $objfilemod = @stat ? $stat[9] : 0;

    # Load from object file. If loading the object file generates an error,
    # or results in a non-component object, try regenerating the object file
    # once before giving up and reporting an error. This can be handy in the
    # rare case of an empty or corrupted object file.  (But add an exception
    # for "Compilation failed in require" errors, since the bad module will
    # be added to %INC and the error will not occur the second time - RT
    # #39803).
    #
    for my $try (1..2) {
        if ( ($objfilemod < $srcmod && !$self->static_source) || $try == 2 ) {
            $self->compile_to_file( $source, $objfile );
        }
        $comp_class = eval { $self->eval_object_code( $objfile ) };
        if (   ( !blessed($comp_class) || !$comp_class->isa('Mason::ComponentClass') )
               && ( !defined($@) || $@ !~ /failed in require/ ) )
        {
            next if $try == 1;
            my $error =
                $@
                ? $@
                : "Could not get Mason::ComponentClass from object file '$objfile'";
            $self->_compilation_error( $source->friendly_name, $error );
        }
    }

    # Save component in the cache.
    #
    $code_cache->{$comp_id} = { lastmod => $srcmod, comp_class => $comp_class };

    return $comp_class;
}

sub resolve_comp_path_to_source {
    my ( $self, $path ) = @_;

    my $resolver = $self->{resolver};
    foreach my $pair ( $self->comp_root_array ) {
        last if $source = $resolver->get_info( $path, @$pair );
    }
    return $source;
}

sub object_dir {
    my $self = shift;
    return catdir( $self->data_dir, 'obj' );
}

sub object_create_marker_file {
    my $self = shift;
    return catfile( $self->object_dir, '.__obj_create_marker' );
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
                my $object_create_marker_file =
                  $self->object_create_marker_file;
                if ( !-e $object_create_marker_file
                    || ( stat($object_create_marker_file) )[9] <
                    $touch_file_lastmod )
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

# Look for component <$name> starting in <$startpath> and moving upwards
# to the root. Return component object or undef.
#
sub find_comp_upwards {
    my ( $self, $startpath, $name ) = @_;
    $startpath =~ s{/+$}{};

    # Don't use File::Spec here, this is a URL path.
    do {
        my $comp = $self->load("$startpath/$name");
        return $comp if $comp;
    } while $startpath =~ s{/+[^/]*$}{};

    return;    # Nothing found
}

sub comp_root_array_as_string {
    my ($self) = @_;

    return join( ", ", map { "'$_->[1]'" } $self->comp_root_array )

}

1;
