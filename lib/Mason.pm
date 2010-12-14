package Mason;
use Carp;
use Log::Any qw($log);
use List::Util qw(first);
use Mason::Interp;
use Mason::Plugin;
use Mason::Util qw(can_load);
use Memoize;
use Moose::Meta::Class;
use strict;
use warnings;

$Mason::VERSION = '0.01';

sub new {
    my ( $class, %params ) = @_;
    my $plugins = delete( $params{plugins} ) || [];
    croak 'plugins must be an array reference' unless ref($plugins) eq 'ARRAY';
    $plugins = $class->process_plugins($plugins);
    my $interp_class = $class->find_subclass( 'Interp', $plugins );
    return $interp_class->new( mason_root_class => $class, plugins => $plugins, %params );
}

sub process_plugins {
    my ( $class, $plugins ) = @_;

    return [ map { $class->process_plugin($_) } @$plugins ];
}

sub process_plugin {
    my ( $class, $plugin ) = @_;
    my @candidates = (
        substr( $plugin, 0, 1 ) eq '+'
        ? ( substr( $plugin, 1 ) )
        : map { join( "::", $_, "Plugin", $plugin ) }
          ( $class eq 'Mason' ? ($class) : ( $class, 'Mason' ) )
    );
    return ( first { can_load($_) } @candidates )
      || die "could not find plugin '$plugin' in " . join( " or ", @candidates );
}

my ( %find_subclass_cache, %final_subclass_seen );

sub find_subclass {
    my ( $class, $name, $plugins ) = @_;
    my $subclass;

    my $key = join( ",", $class, $name, @$plugins );
    return $find_subclass_cache{$key} if defined( $find_subclass_cache{$key} );

    # Look for subclass under root class, then use default
    #
    my $default_subclass = join( "::", "Mason", $name );
    if ( $class eq 'Mason' ) {
        $subclass = $default_subclass;
    }
    else {
        my $try_subclass = join( "::", $class, $name );
        $subclass = can_load($try_subclass) ? $try_subclass : $default_subclass;
    }

    # Apply roles from plugins - adapted from MooseX::Traits
    #
    my $final_subclass;
    my @roles = grep { can_load($_) } map { join( "::", $_, $name ) } @$plugins;
    if (@roles) {
        my $meta = Moose::Meta::Class->create_anon_class(
            superclasses => [$subclass],
            roles        => \@roles,
            cache        => 1
        );
        $final_subclass = $meta->name;
        $meta->add_method( 'meta' => sub { $meta } )
          if !$final_subclass_seen{$final_subclass}++;
    }
    else {
        $final_subclass = $subclass;
    }
    $log->debugf( "find_subclass(%s) - plugins=%s, roles=%s - %s",
        $name, $plugins, \@roles, $final_subclass )
      if $log->is_debug;

    $find_subclass_cache{$key} = $final_subclass;
    return $final_subclass;
}

1;

__END__

=head1 NAME

Mason - High-performance, dynamic web site authoring system

=cut
