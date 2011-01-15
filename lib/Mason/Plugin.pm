package Mason::Plugin;
use Moose::Role;
use Method::Signatures::Simple;
use Mason::Util qw(can_load);
use strict;
use warnings;

method expand_to_plugins ($plugin_class:) {
    return ($plugin_class);
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
