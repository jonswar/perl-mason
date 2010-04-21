package Mason::ComponentClass;
use Moose;
use strict;
use warnings;

has 'name'      => ( required   => 1 );
has 'load_time' => ( default    => sub { time } );
has 'logger'    => ( lazy_build => 1 );

__PACKAGE__->meta->make_immutable();

sub _build_logger {
    my ($self) = @_;

    my $log_category = "Mason::Component" . $self->path();
    $log_category =~ s/\//::/g;
    return Log::Any->get_logger( category => $log_category );
}

1;
