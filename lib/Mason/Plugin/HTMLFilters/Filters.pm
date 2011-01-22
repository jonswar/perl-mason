package Mason::Plugin::HTMLFilters::Filters;
use Mason::PluginRole;

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
