package Mason::Plugin;
use Moose::Role;
use Method::Signatures::Simple;
use Mason::Util qw(can_load);
use namespace::autoclean;

method requires_plugins ($plugin_class:) {
    return ();
}

method expand_to_plugins ($plugin_class:) {
    return ( $plugin_class,
        Mason::PluginManager->process_plugin_specs( [ $plugin_class->requires_plugins ] ) );
}

method get_roles_for_mason_class ($plugin_class: $name) {
    my @roles_to_try = join( "::", $plugin_class, $name );
    if ( $name eq 'Component' ) {
        push( @roles_to_try, join( "::", $plugin_class, 'Filters' ) );
    }
    my @roles = grep { Class::MOP::is_class_loaded($_) || can_load($_) } @roles_to_try;
    return @roles;
}

1;
