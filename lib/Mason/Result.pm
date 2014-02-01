package Mason::Result;

use Mason::Moose;

# Public attributes
has 'data'   => ( default => sub { {} } );
has 'output' => ( is => 'rw', default => '' );

method _append_output ($text) {
    $self->{output} .= $text;
}

__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

Mason::Result - Result returned from Mason request

=head1 SYNOPSIS

    my $interp = Mason->new(...);
    my $output = $result->output;
    my $data   = $result->data;

=head1 DESCRIPTION

An object of this class is returned from C<< $interp->run >>. It contains the
page output and any values set in C<< $m->result >>. Plugins may add additional
accessors.

=head1 METHODS

=over

=item output

The output of the entire page, unless L<out_method|Mason::Request/out_method>
was defined in which case this will be empty.

=item data

A hashref of arbitrary data that can be set via

    $m->result->data->{'key'} = 'value';

=back

=cut
