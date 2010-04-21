# Copyright (c) 1998-2005 by Jonathan Swartz. All rights reserved.
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.

package Mason::Resolver;
use Mason::ComponentSource;
use Mason::Exceptions( abbr => ['param_error', 'virtual_error'] );
use strict;
use warnings;

# Returns Mason::ComponentSource object
sub get_info {
    shift->_virtual;
}

sub glob_path {
    shift->_virtual;
}

sub _virtual
{
    my $self = shift;

    my $sub = (caller(1))[3];
    $sub =~ s/.*::(.*?)$/$1/;
    virtual_error "$sub is a virtual method and must be overridden in " . ref($self);
}

1;

__END__

=head1 NAME

Mason::Resolver - Component path resolver base class

=head1 SYNOPSIS

  # make a subclass and use it

=head1 DESCRIPTION

The resolver is responsible for translating a component path like
/foo/index.html into a component.  By default, Mason expects
components to be stored on the filesystem, and uses the
Mason::Resolver::File class to get information on these
components.

The Mason::Resolver provides a virtual parent class from which
all resolver implementations should inherit.

=head1 Class::Container

This class is used by most of the Mason object's to manage constructor
parameters and has-a relationships with other objects.

See the documentation on this class for details on how to declare what
paremeters are valid for your subclass's constructor.

Mason::Resolver is a subclass of Class::Container so you
do not need to subclass it yourself.

=head1 METHODS

If you are interested in creating a resolver subclass, you must
implement the following methods.

=over 4

=item new

This method is optional.  The new method included in this class is
simply inherited from C<Class::Container>.
If you need something more complicated done in your new method you
will need to override it in your subclass.

=item get_info

Takes three arguments: an absolute component path, a component root key,
and a component root path. Returns a new
L<Mason::ComponentSource|Mason::ComponentSource> object.

=item glob_path

Takes two arguments: a path glob pattern, something
like "/foo/*" or "/foo/*/bar", and a component root path. Returns
a list of component paths for components which match this glob pattern.

For example, the filesystem resolver simply appends this pattern to
the component root path and calls the Perl C<glob()> function to
find matching files on the filesystem.

=back

=head1 SEE ALSO

L<Mason|Mason>

=cut
