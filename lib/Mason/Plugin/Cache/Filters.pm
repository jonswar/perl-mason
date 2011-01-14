package Mason::Plugin::Cache::Filters;
use Method::Signatures::Simple;
use Moose::Role;

method Cache ( $key, $set_options, %cache_options ) {
    Mason::DynamicFilter->new(
        filter => sub {
            $self->cache(%cache_options)->compute( $key, $_[0], $set_options );
        }
    );
}

1;
