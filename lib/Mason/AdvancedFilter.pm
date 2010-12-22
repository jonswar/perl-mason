package Mason::AdvancedFilter;
use Moose;
use Mason::Moose;
use Method::Signatures::Simple;
use strict;
use warnings;

has 'filter' => (isa => 'CodeRef');

around 'BUILDARGS' => sub {
    my $orig  = shift;
    my $class = shift;
    if ( @_ == 1 ) {
        return $class->$orig( filter => $_[0] );
    }
    else {
        return $class->$orig(@_);
    }
};

method apply_filter () {
    my ($yield) = @_;
    return $self->filter->($yield);
}

1;
