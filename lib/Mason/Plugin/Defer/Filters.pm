package Mason::Plugin::Defer::Filters;
use Mason::PluginRole;

method Defer () {
    Mason::DynamicFilter->new(
        filter => sub {
            $self->m->defer( $_[0] );
        }
    );
}

1;
