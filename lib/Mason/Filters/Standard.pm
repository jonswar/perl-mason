package Mason::Filters::Standard;

use Mason::DynamicFilter;
use Mason::Util;
use Mason::PluginRole;

method Capture ($outref) {
    sub { $$outref = $_[0]; return '' }
}

method CompCall ($path, @params) {
    Mason::DynamicFilter->new(
        filter => sub {
            my $m = $self->m;
            return $m->scomp( $path, @params, yield => $_[0] );
        }
    );
}

method NoBlankLines () {
    sub {
        my $text = $_[0];
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

method Tee ($outref) {
    sub { $$outref = $_[0]; return $_[0] }
}

method Trim () {
    sub { Mason::Util::trim( $_[0] ) }
}

1;

__END__

=pod

=head1 NAME

Mason::Filters::Standard - Standard filters

=head1 DESCRIPTION

These filters are automatically composed into
L<Mason::Component|Mason::Component>.

=head1 FILTERS

=over

=item Capture ($ref)

Uses C<< $m->capture >> to capture the content in I<$ref> instead of outputting
it.

    % $.Capture(\my $content) {{
      <!-- this will end up in $content -->
    % }}

    ... do something with $content

=item CompCall ($path, @args...)

Calls the component with I<path> and I<@args>, just as with C<< $m->scomp >>,
with an additional coderef argument C<yield> that can be invoked to generate
the content. Arguments passed to C<yield> can be accessed inside the content
via C<@_>. This is the replacement for Mason 1's L<Components With
Content|http://search.cpan.org/perldoc?HTML::Mason::Devel#Component_Calls_with_Content>.

  In index.mc:
    % $.CompCall ('list_items.mi', items => \@items) {{
    <li><% $_[0] %></li>
    % }}

  In list_items.mi:
    <%class>
    has 'items';
    has 'yield';
    </%class>

    % foreach my $item (@{$.items}) {
    <% $.yield->($item) %>
    % }

=item NoBlankLines

Remove lines with only whitespace from content. This

    % $.NoBlankLines {{

    hello


    world    
    % }}

yields

    hello
    world

=item Repeat ($count)

Repeat the content block I<$count> times. Note that the block is re-executed
each time, which may result in different content.

    <!-- Prints 1 to 5 -->
    % my $i = 1;
    % $.Repeat(5) {{
       <% $i++ %><br>
    % }}

=item Tee ($ref)

Uses C<< $m->capture >> to capture the content in I<$ref>, and also output it.

    % $.Tee(\my $content) {{
      <!-- this will end up in $content and also be output -->
    % }}

    ...

    <!-- output content again down here -->
    <% $content %>

=item Trim

Remove whitespace from the beginning and end of the content.

=back

=head1 SEE ALSO

L<Mason::Manual::Filters|Mason::Manual::Filters>, L<Mason|Mason>

=cut
