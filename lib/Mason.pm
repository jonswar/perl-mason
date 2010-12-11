package Mason;
use Mason::Interp;
use Mason::Util;
use Memoize;
use strict;
use warnings;

$Mason::VERSION = '0.01';

sub new {
    my $class        = shift;
    my $interp_class = $class->find_subclass('Interp');
    return $interp_class->new( mason_root_class => $class, @_ );
}

memoize( \&find_subclass );

sub find_subclass {
    my ( $class, $name ) = @_;
    my $default_subclass = join( "::", "Mason", $name );
    if ( $class eq 'Mason' ) {
        return $default_subclass;
    }
    else {
        my $try_subclass = join( "::", $class, $name );
        return can_load($try_subclass) ? $try_subclass : $default_subclass;
    }
}

1;

__END__

=head1 NAME

Mason - High-performance, dynamic web site authoring system

=cut
