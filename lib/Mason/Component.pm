package Mason::Component;
use Method::Signatures::Simple;
use Moose;
use Log::Any;
use strict;
use warnings;

# Passed attributes
has 'm' => ( is => 'ro', required => 1, weak_ref => 1 );

# Derived attributes
has 'comp_attr' => ( is => 'ro', init_arg => undef );
has 'comp_logger' => ( is => 'ro', init_arg => undef, lazy_build => 1 );

method BUILD ($params) {
    $self->{comp_args} = { map { /^comp_|m$/ ? () : ( $_, $params->{$_} ) } keys(%$params) };
}

method _build_comp_logger () {
    my $log_category = "Mason::Component" . $self->comp_path();
    $log_category =~ s/\//::/g;
    return Log::Any->get_logger( category => $log_category );
}

foreach my $method qw(comp_path comp_dir_path comp_is_external) {
    __PACKAGE__->meta->add_method( $method => sub { return $_[0]->_comp_info->{$method} } );
}

# Default render in case of no wrappers
#
method render () {
    $self->main();
}

# Default dispatch - reject path_info, otherwise call render
#
method dispatch () {
    my $m = $self->m;
    $m->decline if length( $m->path_info );
    $self->render(@_);
}

__PACKAGE__->meta->make_immutable();

1;
