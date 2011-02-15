package Mason::Component;
use Mason::Component::InstanceMeta;
use Moose;    # no Mason::Moose - don't want StrictConstructor
use MooseX::HasDefaults::RO;
use Method::Signatures::Simple;
use namespace::autoclean;
use Log::Any;

with 'Mason::Filters::Standard';

# Passed attributes
#
has 'm' => ( required => 1, weak_ref => 1 );

method BUILD ($params) {
    $self->{_orig_params} = $params;
}

method cmeta () {
    if ( ref($self) ) {
        if ( !$self->{cmeta} ) {
            my $orig_params = $self->{_orig_params};
            my $cmeta_args =
              { map { /^cmeta|m$/ ? () : ( $_, $orig_params->{$_} ) } keys(%$orig_params) };
            my $component_instance_meta_class = $self->m->interp->component_instance_meta_class;
            $self->{cmeta} = $component_instance_meta_class->new(
                args        => $cmeta_args,
                class_cmeta => $self->_class_cmeta,
                instance    => $self,
            );
        }
        return $self->{cmeta};
    }
    else {
        return $self->can('_class_cmeta') ? $self->_class_cmeta : undef;
    }
}

# Default handle - call render
#
method handle () {
    $self->render(@_);
}

# Default render - call wrap
#
method render () {
    $self->wrap(@_);
}

# Top wrap
#
method wrap () {
    inner();
}

# By default, do not allow path_info
#
method allow_path_info () {
    return 0;
}

__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

Mason::Component - Mason Component base class

=head1 DESCRIPTION

Every Mason component corresponds to a unique class that inherits, directly or
indirectly, from this base class.

A new instance of the component class is created whenever a component is called
- whether via a top level request, C<< <& &> >> tags, or an << $m->comp >>
call.

We leave this class as devoid of built-in methods as possible, allowing you to
create methods in your own components without worrying about name clashes.

=head1 STRUCTURAL METHODS

This is the standard call chain for the page component (the initial component
of a request).

    handle -> render -> wrap -> main

In many cases only C<main> will actually do anything.

=over

=item handle

This is the top-most method called on the page component. Its job is to decide
how to handle the request, e.g.

=over

=item *

throw an error (e.g. permission denied)

=item *

defer to another component via C<< $m->go >>

=item *

redirect to another URL (if in a web environment)

=item *

render the page

=back

It should not output any content itself. By default, it simply calls
L</render>.

=item render

This method is invoked from L</handle> on the page component. Its job is to
output the full content of the page. By default, it simply calls L</wrap>.

=item wrap

This method is invoked from L</render> on the page component.  By convention,
C<wrap> is an L<augmented|Moose::Manual::MethodModifiers/INNER AND AUGMENT>
method, with each superclass calling the next subclass.  This is useful for
cascading templates in which the top-most superclass generates the surrounding
content.

By default, C<wrap> simply calls C<< inner() >> to go to the next subclass, and
then L</main> at the bottom subclass.

=item main

This method is invoked when a non-page component is called, and from the
default L</wrap> method as well. It consists of the code and output in the main
part of the component that is not inside a C<< <%method> >> or C<< <%class> >>
tag.

=back

=head1 OTHER METHODS

=over

=item m

Returns the current request. This is also available via C<< $m >> inside Mason
components.

=item cmeta

Returns a meta object associated with this component, containing information
such as the component's path and source file. It will be a
L<Mason::Component::InstanceMeta> object if called on a component instance, and
a L<Mason::Component::ClassMeta> object if called on a component class; the
former contains slightly more information.

    my $path = $self->cmeta->path;

=back

=cut
