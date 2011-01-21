package Mason;
use Carp;
use List::Util qw(first);
use Mason::Interp;
use Mason::PluginManager;
use Moose;
use strict;
use warnings;

sub new {
    my ( $class, %params ) = @_;

    # Extract plugins and base_interp_class
    #
    my $plugin_specs      = delete( $params{plugins} )           || [];
    my $base_interp_class = delete( $params{base_interp_class} ) || 'Mason::Interp';

    # Process plugins and determine real interp_class
    #
    my @plugins = Mason::PluginManager->process_top_plugin_specs($plugin_specs);
    my $interp_class =
      Mason::PluginManager->apply_plugins_to_class( $base_interp_class, 'Interp', \@plugins );

    # Create and return interp
    #
    return $interp_class->new( mason_root_class => $class, plugins => \@plugins, %params );
}

my ( %apply_plugins_cache, %final_subclass_seen );

1;

# ABSTRACT: Powerful class-based templating system
__END__

=pod
