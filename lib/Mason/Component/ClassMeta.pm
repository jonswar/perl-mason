package Mason::Component::ClassMeta;
use File::Basename;
use Mason::Moose;
use Log::Any;

my $next_id = 0;

# Passed attributes (generated in compiled component)
has 'class'        => ( required => 1 );
has 'dir_path'     => ( required => 1 );
has 'interp'       => ( required => 1, weak_ref => 1 );
has 'is_dhandler'  => ( init_arg => undef, lazy_build => 1 );
has 'is_top_level' => ( required => 1 );
has 'object_file'  => ( required => 1 );
has 'path'         => ( required => 1 );
has 'source_file'  => ( required => 1 );

# Derived attributes
has 'id'   => ( init_arg => undef, default => sub { $next_id++ } );
has 'log'  => ( init_arg => undef, lazy_build => 1 );
has 'name' => ( init_arg => undef, lazy_build => 1 );

method _build_is_dhandler () {
    return grep { $self->name eq $_ } @{ $self->interp->dhandler_names };
}

method _build_log () {
    my $log_category = "Mason::Component" . $self->path;
    $log_category =~ s/\//::/g;
    return Log::Any->get_logger( category => $log_category );
}

method _build_name () {
    return basename( $self->path );
}

__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

Mason::Component::ClassMeta - Meta-information about Mason component class

=head1 SYNOPSIS

    # In a component:
    My path is <% $.cmeta->path %>
    My source file is <% $.cmeta->source_file %>

=head1 DESCRIPTION

Every L<Mason::Component|Mason::Component> class has an associated
L<Mason::Component::ClassMeta|Mason::Component::ClassMeta> object, containing
meta-information such as the component's path and source file. It can be
accessed with the L<cmeta|Mason::Component/cmeta> method.

=over

=item class

The component class that this meta object is associated with.

=item dir_path

The directory of the component path, relative to the component root - e.g. for
a component '/foo/bar', the dir_path is '/foo'.

=item is_top_level

Whether the component is considered "top level", accessible directly from C<<
$interp->run >> or a web request. See L<Interp/top_level_extensions>.

=item name

The component base name, e.g. 'bar' for component '/foo/bar'.

=item object_file

The object file produced from compiling the component.

=item path

The component path, relative to the component root - e.g. '/foo/bar'.

=item source_file

The component source file.

=back

=head1 SEE ALSO

L<Mason|Mason>

=cut
