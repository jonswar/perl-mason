package Mason::Plugin::AdvancedPageResolution::Request;
use Mason::PluginRole;

has 'declined_paths' => ( default => sub { {} } );
has 'path_info'  => ( init_arg => undef, default => '' );

method decline () {

    # Add current path to declined paths, and reissue request
    #
    $self->go( { declined_paths => { %{ $self->declined_paths }, $self->page->cmeta->path => 1 } },
        $self->request_path, %{ $self->request_args } );
}

method resolve_page_component ($request_path) {
    return $self->interp->resolve_page_component_method->( $self, $request_path );
}

1;
