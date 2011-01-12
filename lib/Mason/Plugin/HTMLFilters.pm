package Mason::Plugin::HTMLFilters;
use Moose;
extends 'Mason::Plugin';

package Mason::Plugin::HTMLFilters::Filters;
use Method::Signatures::Simple;
use Moose::Role;
use strict;
use warnings;

my %html_escape = ( '&' => '&amp;', '>' => '&gt;', '<' => '&lt;', '"' => '&quot;' );
my $html_escape = qr/([&<>"])/;

method HTML () {
    sub {
        my $text = $_[0];
        $text =~ s/$html_escape/$html_escape{$1}/mg;
        return $text;
    };
}
*H = *HTML;

method HTMLEntities (@args) {
    require HTML::Entities;
    sub {
        HTML::Entities::encode_entities( $_[0], @args );
    };
}

method URI () {
    use bytes;
    sub {
        my $text = $_[0];
        $text =~ s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
        return $text;
    };
}

method HTMLPara () {
    sub {
        my $text = $_[0];
        return "<p>\n" . join( "\n</p>\n\n<p>\n", split( /(?:\r?\n){2,}/, $text ) ) . "</p>\n";
    };
}

method HTMLParaBreak () {
    sub {
        my $text = $_[0];
        $text =~ s|(\r?\n){2,}|$1<br />$1<br />$1|g;
        return $text;
    };
}

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
