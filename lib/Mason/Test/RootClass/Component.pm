package Mason::Test::RootClass::Component;
use Moose;
extends 'Mason::Component';

# This doesn't work - it interrupts the inner() chain. Investigate later.
#
#  before 'render' => sub {
#      my ($self) = @_;
#      print STDERR "starting component render - " . $self->cmeta->path . "\n";
#  };

__PACKAGE__->meta->make_immutable();

1;
