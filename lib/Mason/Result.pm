package Mason::Result;
use Mason::Moose;

# Public attributes
has 'output' => ( required => 1 );

__PACKAGE__->meta->make_immutable();

1;

# ABSTRACT: Result returned from Mason request
__END__

=pod

=head1 SYNOPSIS

    my $interp = Mason->new(...);
    my $output = $result->output;

=head1 DESCRIPTION

An object of this class is returned from C<< $interp->run >>. By default it
contains just the page output, but plugins may add additional accessors.

=head1 METHODS

=over

=item output

The output of the entire page, unless L<Mason::Request/out_method> was defined
in which case this will be empty.

=back

=cut
