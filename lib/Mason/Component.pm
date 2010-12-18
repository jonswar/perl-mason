package Mason::Component;
use Method::Signatures::Simple;
use Moose;    # Not Mason::Moose - we don't want strict constructor
use MooseX::HasDefaults::RO;
use Log::Any;
use strict;
use warnings;

# Passed attributes
has 'm' => ( required => 1, weak_ref => 1 );

# Derived attributes
has 'comp_attr' => ( init_arg => undef );
has 'comp_cache' => ( init_arg => undef, lazy_build => 1 );
has 'comp_logger' => ( init_arg => undef, lazy_build => 1 );

method BUILD ($params) {
    $self->{comp_attr} = { map { /^comp_|m$/ ? () : ( $_, $params->{$_} ) } keys(%$params) };
}

method _build_comp_cache () {
    my $chi_root_class = $self->m->interp->chi_root_class;
    load_class($chi_root_class);
    my %options = ( %{ $self->m->interp->chi_default_params }, @_ );
    if ( !exists( $options{namespace} ) ) {
        $options{namespace} = $self->comp_path;
    }
    return $chi_root_class->new(%options);
}

method _build_comp_logger () {
    my $log_category = "Mason::Component" . $self->comp_path();
    $log_category =~ s/\//::/g;
    return Log::Any->get_logger( category => $log_category );
}

foreach my $method qw(comp_path comp_dir_path comp_is_external) {
    __PACKAGE__->meta->add_method( $method => sub { return $_[0]->_comp_info->{$method} } );
}

method comp_title () {
    return $self->comp_path;
}

# Top render
#
method render () {
    inner();
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

=head1 NAME

Mason::Component - Mason Component base class

=head1 DESCRIPTION

Every Mason component corresponds to a unique class that inherits, directly or
indirectly, from this base class.

Whenever a component is called - whether via a top level request, C<< <& &> >>
tags, or an << $mm->comp >> call - a new instance of the component class is
created and a method is called on it (C<dispatch> at the top level, C<main>
otherwise).

=head1 STRUCTURAL METHODS

=over

=item dispatch

This method is invoked on the page component at the beginning of the request.

By default, it calls L</render> if C<< $m->path_info >> is empty, and calls C<<
$m->decline >> otherwise.

This is the place to process C<< $m->path_info >> or other arguments and take
appropriate action before rendering starts.

=item render

This method is invoked from dispatch on the page component. By convention,
render operates in an inverted direction: the superclass method gets to act
before and after the subclass method. See "Content wrapping" for more
information.

=item main

This method is invoked when a non-top-level component is called, and from the
default render method as well. It consists of the code and output in the main
part of the component that is not inside a C<< <%method> >> or C<< <%class> >>
tag.

=back

=head1 OTHER METHODS

To avoid name clashes with developers' own component methods, whenever
feasible, future built-in methods will be prefixed with "comp_".

=over

=item m

Returns the current request.

=item comp_attr

Returns the full hashref of attributes that the component was called with.

=item comp_path

Returns the component path, relative to the component root - e.g. '/foo/bar'.

=back

=head1 SEE ALSO

L<Mason|Mason>

=cut

1;
