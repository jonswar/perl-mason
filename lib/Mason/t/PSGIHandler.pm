package Mason::t::PSGIHandler;
use Test::Class::Most parent => 'Mason::Test::Class';
use Mason::Util qw(trim);
use HTTP::Request::Common;
use Plack::Test;

__PACKAGE__->default_plugins( ['PSGIHandler'] );

sub test_psgi_comp {
    my ( $self, %params ) = @_;
    my $interp = $self->interp;
    my $app    = sub { my $env = shift; $interp->handle_psgi($env) };
    my $path   = $params{path} or die "must pass path";
    $self->add_comp( path => $path, src => $params{src} );
    test_psgi(
        $app,
        sub {
            my $cb  = shift;
            my $res = $cb->( GET $path );
            if ( my $expect_content = $params{expect_content} ) {
                is( trim( $res->content ), trim($expect_content), "$path - content" );
            }
            if ( my $expect_code = $params{expect_code} ) {
                is( $res->code, $expect_code, "$path - code" );
            }
            if ( my $expect_headers = $params{expect_headers} ) {
                while ( my ( $hdr, $value ) = each(%$expect_headers) ) {
                    cmp_deeply( $res->header($hdr), $value, "$path - header $hdr" );
                }
            }
        }
    );
}

sub test_basic : Tests(2) {
    my $self = shift;
    $self->test_psgi_comp(
        path           => '/hi.m',
        src            => 'path = <% $m->req->path %>',
        expect_content => 'path = /hi.m',
        expect_code    => 200
    );
}

sub test_abort : Tests(8) {
    my $self = shift;
    $self->test_psgi_comp(
        path => '/redirect.m',
        src  => '
will not be printed
% $m->redirect("http://www.google.com/");
',
        expect_content => ' ',
        expect_code    => 302,
        expect_headers => { Location => 'http://www.google.com/' },
    );
    $self->test_psgi_comp(
        path => '/redirect_301.m',
        src  => '
will not be printed
% $m->redirect("http://www.yahoo.com/", 301);
',
        expect_content => ' ',
        expect_code    => 301,
        expect_headers => { Location => 'http://www.yahoo.com/' },
    );
    $self->test_psgi_comp(
        path => '/not_found.m',
        src  => '
will not be printed
% $m->clear_and_abort(404);
',
        expect_content => ' ',
        expect_code    => 404,
    );
}

1;
