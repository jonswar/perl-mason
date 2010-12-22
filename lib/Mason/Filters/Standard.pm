package Mason::Filters::Standard;
use Mason::AdvancedFilter;
use Mason::Util;
use Method::Signatures::Simple;
use Moose::Role;
use strict;
use warnings;

method Cache ( $key, $set_options ) {
    Mason::AdvancedFilter->new(
        filter => sub {
            $self->cmeta->cache->compute( $key, $_[0], $set_options );
        }
    );
}

method Capture ($outref) {
    sub { $$outref = $_[0]; return '' }
}

method Defer () {
    Mason::AdvancedFilter->new(
        filter => sub {
            $self->m->defer( $_[0] );
        }
    );
}

method NoBlankLines () {
    sub {
        my $text = shift;
        $text =~ s/^\n$//mg;
        return $text;
    };
}

method Repeat ($times) {
    Mason::AdvancedFilter->new(
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
