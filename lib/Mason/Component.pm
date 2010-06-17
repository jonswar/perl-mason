package Mason::Component;
use Moose;
use Log::Any;
use strict;
use warnings;

# Passed attributes
has 'comp_request' => ( is => 'ro', required => 1, weak_ref => 1 );

# Derived attributes
has 'comp_logger' => ( is => 'ro', lazy_build => 1 );

__PACKAGE__->meta->make_immutable();

sub _build_comp_logger {
    my ($self) = @_;

    my $log_category = "Mason::Component" . $self->comp_path();
    $log_category =~ s/\//::/g;
    return Log::Any->get_logger( category => $log_category );
}

sub render {
    my ($self) = @_;

    $self->main();
}

1;
