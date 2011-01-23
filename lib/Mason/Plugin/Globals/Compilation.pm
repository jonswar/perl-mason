package Mason::Plugin::Globals::Compilation;
use Mason::PluginRole;

around '_output_class_header' => sub {
    my $orig = shift;
    my $self = shift;
    return join( "\n", $self->$orig(@_), $self->global_declarations );
};

method global_declarations () {
    return join( "\n", map { $self->global_declaration($_) } @{ $self->interp->allow_globals } );
}

method global_declaration ($spec) {
    my ( $sigil, $name ) = $self->interp->_parse_global_spec($spec);
    return sprintf( 'our %s%s; *%s = \%s%s::%s;' . "\n",
        $sigil, $name, $name, $sigil, $self->interp->globals_package, $name );
}

1;
