package Mason::Result;
use Moose;
use Mason::Moose;
use strict;
use warnings;

# Public attributes
has 'output' => ( required => 1 );
has 'retval' => ( required => 1 );

__PACKAGE__->meta->make_immutable();

1;

__END__

=head1 NAME

Mason::Result - Result returned from request

=head1 SYNOPSIS

    my $interp = Mason->new(...);
    my $result = $interp->run(...);
    my $output = $result->output;

=head1 DESCRIPTION

An object of this class is returned from C<< $interp->run >>. By default it
contains just the page output and return value, but plugins may add additional
accessors.

=over

=item output

The output of the entire page, unless L<Mason::Request/out_method> was defined
in which case this will be empty.

=item retval

The return value from the page component, or undef if it did not return
anything (usually the case).

=back

=cut
