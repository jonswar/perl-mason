package Mason::Plugin::ResolveURI::Request;
use Mason::PluginRole;

has 'declined'  => ( init_arg => undef, is => 'rw' );
has 'path_info' => ( init_arg => undef, default => '' );

method has_path_info () {
    return length( $self->path_info ) > 0;
}

method decline () {
    $self->declined(1);
    $self->clear_and_abort;
}

around 'run' => sub {
    my $orig = shift;
    my $self = shift;
    my $uri  = shift;
    my $result;
    while (1) {
        my $path = $self->resolve_uri_to_path($uri) || $self->request_path_not_found($uri);
        $result = $self->$orig( $path, @_ );
        last unless $self->declined;
        $self->{declined_paths}->{$path} = 1;
        $self->declined(0);
    }
    return $result;
};

method resolve_uri_to_path ($uri) {
    return $self->interp->resolve_uri_to_path->( $self, $uri );
}

1;
