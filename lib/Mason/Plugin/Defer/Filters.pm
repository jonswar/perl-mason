package Mason::Plugin::Defer::Filters;
use Method::Signatures::Simple;
use Moose::Role;
use namespace::autoclean;

method Defer () {
    Mason::DynamicFilter->new(
        filter => sub {
            $self->m->defer( $_[0] );
        }
    );
}

1;
