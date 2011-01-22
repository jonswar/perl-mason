package Mason::Plugin::Cache::Filters;
use Mason::PluginRole;

method Cache ( $key, $set_options, %cache_options ) {
    Mason::DynamicFilter->new(
        filter => sub {
            $self->cache(%cache_options)->compute( $key, $_[0], $set_options );
        }
    );
}

1;
