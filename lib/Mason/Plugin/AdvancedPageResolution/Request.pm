package Mason::Plugin::AdvancedPageResolution::Request;
use Mason::Moose::Role;

has 'path_info'  => ( init_arg => undef, default => '' );

method resolve_page_component ($request_path) {
    return $self->interp->resolve_page_component_method->( $self, $request_path );
}

1;
