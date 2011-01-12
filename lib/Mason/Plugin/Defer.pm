package Mason::Plugin::Defer;
use Moose;
extends 'Mason::Plugin';

1;

# ABSTRACT: Defer computing parts of output until the end of the request
__END__

=head1 SYNOPSIS

    <head>
    <title><% $m->defer(sub { $m->page->title }) %></title>

    <% $.Defer { %>
    % my $content = join(", ", @{ $m->page->meta_content });
    <meta name="description" content="<% $content %>">
    </%>

    <body>
    ...

=head1 DESCRIPTION

The I<defer> feature allows sections of output to be deferred til the end of
the request. You can set up multiple deferred code blocks which will execute
and insert themselves into the output stream at request end.

=head1 REQUEST METHOD

=over

=item defer (code)

Returns a marker string that is unique and will not appear in normal output. At
the end of the request, each marker string is replaced with the output of its
associated code. e.g.

    <title><% $m->defer(sub { $m->page->title }) %></title>

=back

=head1 FILTER

=over

=item Defer

Applies C<< $m->defer >> to the content block. e.g.

    <% $.Defer { %>
    % my $content = join(", ", @{ $m->page->meta_content });
    <meta name="description" content="<% $content %>">
    </%>

=back

=head1 AUTHORS

Jonathan Swartz <swartz@pobox.com>

=head1 SEE ALSO

L<Mason|Mason>

=cut
