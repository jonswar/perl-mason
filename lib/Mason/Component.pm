package Mason::Component;
use Mason::Component::InstanceMeta;
use Moose;    # Not Mason::Moose - we don't want strict constructor
use Method::Signatures::Simple;
use MooseX::HasDefaults::RO;
use Log::Any;
use namespace::autoclean;

# Bring in standard filters
with 'Mason::Filters::Standard';

# Passed attributes
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
        return $self->_class_cmeta;
    }
}

# Top wrap
#
method wrap () {
    inner();
}

# Default render - call wrap
#
method render () {
    $self->wrap(@_);
}

# Default dispatch - reject path_info, otherwise call render
#
method dispatch () {
    my $m = $self->m;

    # Not sure about this.
    # $m->decline if length( $m->path_info );
    $self->render(@_);
}

__PACKAGE__->meta->make_immutable();

1;

# ABSTRACT: Mason Component base class
__END__

=head1 DESCRIPTION

Every Mason component corresponds to a unique class that inherits, directly or
indirectly, from this base class.

A new instance of the component class is created whenever a component is called
- whether via a top level request, C<< <& &> >> tags, or an << $m->comp >>
call.

We leave this class as devoid of built-in methods as possible, alllowing you to
create methods in your own components without worrying about name clashes.

=head1 STRUCTURAL METHODS

This is the standard call chain for the page component (the initial component
of a request).

    dispatch -> render -> wrap -> main

In many cases only C<main> will actually do anything.

=over

=item dispatch

This method is invoked on the page component at the beginning of the request.

By default, it calls L</render> if C<< $m->path_info >> is empty, and calls C<<
$m->decline >> otherwise.

This is the place to process C<< $m->path_info >> or other arguments and take
appropriate action before rendering starts.

=item render

This method is invoked from dispatch on the page component. By default, it
calls L</wrap>.

=item wrap

By convention, C<wrap> operates in an inverted direction: the superclass method
gets to act before and after the subclass method. See "Content wrapping" for
more information. By default, C<wrap> just calls C<< $m->call_next >> to go to
the next subclass, and then L</main> at the final subclass.

=item main

This method is invoked when a non-top-level component is called, and from the
default render method as well. It consists of the code and output in the main
part of the component that is not inside a C<< <%method> >> or C<< <%class> >>
tag.

=back

=head1 OTHER METHODS

=over

=item m

Returns the current request. This is also available via C<< $m >> inside Mason
components.

=item cmeta

Returns the L<Mason::Component::Meta|Mason::Component::Meta> object associated
with this component, containing information such as the component's path and
source file.

    my $path = $self->cmeta->path;

=back

=cut
