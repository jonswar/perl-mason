package Mason::AdvancedFilter;
use Moose;
use Mason::Moose;
use Method::Signatures::Simple;
use strict;
use warnings;

has 'filter' => (isa => 'CodeRef');

method apply_filter  () {
    my ($yield) = @_;
    return $self->filter->($yield);
}

1;
