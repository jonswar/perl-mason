package Mason::Plugin::AdvancedPageResolution::Component;
use Mason::PluginRole;

method is_dhandler  () {
    return grep { $self->cmeta->name eq $_ } @{ $self->m->interp->dhandler_names };
}

method accept () {
    $DB::single = 1;
    my $m = $self->m;
    if ( $m->has_path_info && !$m->path_info_accessed && !$self->is_dhandler ) {
        $m->decline( "got path_info - " . $m->path_info );
    }
}

1;
