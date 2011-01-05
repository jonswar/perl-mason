package Mason;
use Carp;
use Log::Any qw($log);
use List::Util qw(first);
use Mason::Interp;
use Mason::Plugin;
use Mason::Util qw(can_load);
use Memoize;
use Moose;
use Moose::Meta::Class;
use MooseX::ClassAttribute;
use strict;
use warnings;

$Mason::VERSION = '0.01';

class_has 'default_plugins' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );

sub new {
    my ( $class, %params ) = @_;
    my $plugins = delete( $params{plugins} ) || [];
    croak 'plugins must be an array reference' unless ref($plugins) eq 'ARRAY';
    $plugins = $class->process_plugins( [ @$plugins, @{ $class->default_plugins } ] );
    my $base_interp_class = delete( $params{base_interp_class} ) || 'Mason::Interp';
    my $interp_class = $class->apply_plugins( $base_interp_class, 'Interp', $plugins );
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

my ( %apply_plugins_cache, %final_subclass_seen );

# Apply roles from plugins - adapted from MooseX::Traits
#
sub apply_plugins {
    my ( $class, $base_subclass, $name, $plugins ) = @_;
    my $subclass;

    my $key = join( ",", $class, $base_subclass, @$plugins );
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

__END__

=head1 NAME

Mason - High-performance, dynamic web site authoring system

=cut
