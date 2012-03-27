package Mason::PluginManager;
use Carp;
use Log::Any qw($log);
use Mason::Moose;
use Mason::Util qw(can_load uniq);

my ( %apply_plugins_cache, %final_subclass_seen );

# CLASS METHODS
#

our $depth;
our %visited;
my $max_depth = 16;

method process_top_plugin_specs ($class: $plugin_specs) {
    local $depth   = 0;
    local %visited = ();

    my @positive_plugin_specs = grep { !/^\-/ } @$plugin_specs;
    my @negative_plugin_specs = map { substr( $_, 1 ) } grep { /^\-/ } @$plugin_specs;
    push( @positive_plugin_specs, '@Default' );
    my %exclude_plugin_modules =
      map { ( $_, 1 ) } $class->process_plugin_specs( \@negative_plugin_specs );

    my @modules =
      grep { !$exclude_plugin_modules{$_} } $class->process_plugin_specs( \@positive_plugin_specs );

    return @modules;
}

method process_plugin_specs ($class: $plugin_specs) {
    local $depth   = $depth + 1;
    local %visited = %visited;
    die ">$max_depth levels deep in process_plugins_list (plugin cycle?)" if $depth >= $max_depth;
    croak 'plugins must be an array reference' unless ref($plugin_specs) eq 'ARRAY';
    my @modules = ( uniq( map { $class->process_plugin_spec($_) } @$plugin_specs ) );
    return @modules;
}

method process_plugin_spec ($class: $plugin_spec) {
    my $module = $class->plugin_spec_to_module($plugin_spec);
    my @modules = !$visited{$module}++ ? $module->expand_to_plugins : ();
    return @modules;
}

method plugin_spec_to_module ($class: $plugin_spec) {
    my $module =
        substr( $plugin_spec, 0, 1 ) eq '+' ? ( substr( $plugin_spec, 1 ) )
      : substr( $plugin_spec, 0, 1 ) eq '@'
      ? ( "Mason::PluginBundle::" . substr( $plugin_spec, 1 ) )
      : "Mason::Plugin::$plugin_spec";
    return can_load($module)
      ? $module
      : die "could not load '$module' for plugin spec '$plugin_spec'";
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

    $final_subclass->meta->make_immutable if $final_subclass->can('meta');

    $apply_plugins_cache{$key} = $final_subclass;
    return $final_subclass;
}

__PACKAGE__->meta->make_immutable();

1;
