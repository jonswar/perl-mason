package Mason::Filters::Standard;
use Mason::DynamicFilter;
use Mason::Util;
use Method::Signatures::Simple;
use Moose::Role;
use strict;
use warnings;

method Cache ( $key, $set_options ) {
    Mason::DynamicFilter->new(
        filter => sub {
            $self->cmeta->cache->compute( $key, $_[0], $set_options );
        }
    );
}

method Capture ($outref) {
    sub { $$outref = $_[0]; return '' }
}

method NoBlankLines () {
    sub {
        my $text = $_[0];
        $DB::single = 1;
        $text =~ s/^\s*\n//mg;
        return $text;
    };
}

method Repeat ($times) {
    Mason::DynamicFilter->new(
        filter => sub {
            my $content = '';
            for ( my $i = 0 ; $i < $times ; $i++ ) {
                $content .= $_[0]->();
            }
            return $content;
        }
    );
}

method Trim () {
    sub { Mason::Util::trim( $_[0] ) }
}

1;

__END__

=head1 NAME

Mason::Filters::Standard - Standard filters

=head1 DESCRIPTION

These filters are automatically composed into
L<Mason::Component|Mason::Component>.

=head1 FILTERS

=over

=item Cache ($key, $set_options)

Caches the content using C<< $m->cache >> and the supplied cache I<$key>.
I<$set_options>, if provided, is passed as the third argument to C<<
$m->cache->set >>.

    <% $.Cache($my_key, '1 hour') { %>
      <!-- this will be cached for an hour -->
    </%>

=item Capture ($ref)

Uses C<< $m->capture >> to capture the content in I<$ref>.

    <% $.Capture(\my $content) { %>
      <!-- this will end up in $content -->
    </%>

    ... do something with $content

=item NoBlankLines

Remove lines with only whitespace from content.

=item Repeat ($count)

Repeat the content block I<$count> times. Note that the block is re-executed
each time, which may result in different content.

    <!-- Prints 1 to 5 -->
    % my $i = 1; 
    <% $.Repeat(5) { %>
       <% $i++ %><br>
    </%>

=item Trim

Remove whitespace from the beginning and end of the content.

=back

=head1 SEE ALSO

L<Mason|Mason>

=cut
