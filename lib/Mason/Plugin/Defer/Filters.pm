package Mason::Plugin::Defer::Filters;
use Method::Signatures::Simple;
use Moose::Role;
use strict;
use warnings;

method Defer () {
    Mason::DynamicFilter->new(
        filter => sub {
            $self->m->defer( $_[0] );
        }
    );
}

1;
