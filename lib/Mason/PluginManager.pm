package Mason::PluginManager;
use Carp;
use List::MoreUtils qw(uniq);
use Log::Any qw($log);
use Moose;
use Mason::Moose;
use Mason::Util qw(can_load);
use strict;
use warnings;

my ( %apply_plugins_cache, %final_subclass_seen );

# CLASS METHODS
#

our $depth = 0;

method process_plugins_list ($class: $plugins) {
    local $depth = $depth + 1;
    die "10 levels deep in process_plugins_list (plugin cycle?)" if $depth >= 10;
    croak 'plugins must be an array reference' unless ref($plugins) eq 'ARRAY';
    $plugins =
      [ uniq( map { $_->expand_to_plugins } map { $class->process_plugin_name($_) } @$plugins ) ];
    return $plugins;
}

method process_plugin_name ($class: $plugin) {
    my $module =
        substr( $plugin, 0, 1 ) eq '+' ? ( substr( $plugin, 1 ) )
      : substr( $plugin, 0, 1 ) eq '@' ? ( "Mason::PluginBundle::" . substr( $plugin, 1 ) )
      :                                  "Mason::Plugin::$plugin";
    return can_load($module) ? $module : die "could not load '$module'";
}

method apply_plugins_to_class ($class: $base_subclass, $name, $plugins) {
    my $subclass;
    my $key = join( ",", $base_subclass, @$plugins );
    return $apply_plugins_cache{$key} if defined( $apply_plugins_cache{$key} );

    my $final_subclass;
    my @roles = map { $_->get_roles_for_mason_class($name) } @$plugins;
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
