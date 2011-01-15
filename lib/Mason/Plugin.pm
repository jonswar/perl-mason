package Mason::Plugin;
use Carp;
use Log::Any qw($log);
use Moose;
use Mason::Moose;
use Mason::Util qw(can_load);
use strict;
use warnings;

my ( %apply_plugins_cache, %final_subclass_seen );

# CLASS METHODS
#

method process_plugins_list ($class: $plugins) {
    croak 'plugins must be an array reference' unless ref($plugins) eq 'ARRAY';
    $plugins = [ map { $class->process_plugin($_) } @$plugins ];
}

method process_plugin ($class: $plugin) {
    my $module =
        substr( $plugin, 0, 1 ) eq '+' ? ( substr( $plugin, 1 ) )
      : substr( $plugin, 0, 1 ) eq '@' ? ( "Mason::PluginBundle::" . substr( $plugin, 0, 1 ) )
      :                                  "Mason::Plugin::$plugin";
    return can_load($module) ? $module : die "could not load '$module'";
}

method apply_plugins_to_class ($class: $base_subclass, $name, $plugins) {
    my $subclass;
    my $key = join( ",", $base_subclass, @$plugins );
    return $apply_plugins_cache{$key} if defined( $apply_plugins_cache{$key} );

    my $final_subclass;
    my @roles_to_try = map { join( "::", $_, $name ) } @$plugins;
    if ( $name eq 'Component' ) {
        push( @roles_to_try, map { join( "::", $_, 'Filters' ) } @$plugins );
    }
    my @roles = grep { Class::MOP::is_class_loaded($_) || can_load($_) } @roles_to_try;
    if (@roles) {
        my $meta = Moose::Meta::Class->create_anon_class(
            superclasses => [$base_subclass],
            roles        => \@roles,
            cache        => 1
        );
        $final_subclass = $meta->name;
        $meta->add_method( 'meta' => sub { $meta } )
          if !$final_subclass_seen{$final_subclass}++;
    }
    else {
        $final_subclass = $base_subclass;
    }
    $log->debugf( "apply_plugins - base_subclass=%s, name=%s, plugins=%s, roles=%s - %s",
        $base_subclass, $name, $plugins, \@roles, $final_subclass )
      if $log->is_debug;

    $apply_plugins_cache{$key} = $final_subclass;
    return $final_subclass;
}

1;
