package Mason::Plugin::HTMLFilters;
use Moose;
with 'Mason::Plugin';

1;

# ABSTRACT: HTML filters
__END__

=head1 DESCRIPTION

Filters related to HTML generation.

=head1 FILTERS

=over

=item HTML or H

Do a basic HTML escape on the content - just the characters '&', '>', '<', and
'"'.

=item HTMLEntities

Do a comprehensive HTML escape on the content, using
HTML::Entities::encode_entities.

=item URI

URI-escape the content.

=item HTMLPara

Formats a block of text into HTML paragraphs.  A sequence of two or more
newlines is used as the delimiter for paragraphs which are then wrapped in HTML
""<p>""...""</p>"" tags. Taken from L<Template::Toolkit|Template>.

=item HTMLParaBreak

Similar to HTMLPara above, but uses the HTML tag sequence "<br><br>" to join
paragraphs. Taken from L<Template::Toolkit|Template>.

=back

=head1 SEE ALSO

L<Mason|Mason>

=cut
