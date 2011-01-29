package Mason::Plugin::AdvancedPageResolution::Request;
use Log::Any qw($log);
use Mason::PluginRole;

has 'declined_paths'     => ( default => sub { {} } );
has 'path_info'          => ( reader => 'peek_path_info', init_arg => undef, default => '' );
has 'path_info_accessed' => ( is => 'rw', init_arg => undef, default => 0 );

method path_info () {
    $self->path_info_accessed(1);
    return $self->peek_path_info;
}

method has_path_info () {
    return length( $self->peek_path_info ) > 0;
}

method decline ($reason) {
    $self->{declined} = $reason || 'no reason';
    $self->abort();
}

override 'resolve_and_render_path' => sub {
    my $self = shift;
  loop: {
        super();
        if ( defined( my $reason = $self->{declined} ) ) {
            my $path = $self->page->cmeta->path;
            $self->{declined_paths}->{$path} = $reason;
            $log->debug("declined '$path': '$reason'")
              if $log->is_debug;
            undef $self->{declined};
            redo loop;
        }
    }
};

override 'dispatch_to_page_component' => sub {
    my ( $self, $page ) = @_;
    $self->catch_abort(
        sub {
            $self->path_info_accessed(0);
            $page->accept();
            $page->render();
        }
    );
};

method resolve_page_component ($request_path) {
    return $self->interp->resolve_page_component_method->( $self, $request_path );
}

1;
