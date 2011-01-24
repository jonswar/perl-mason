package Mason::t::PSGIHandler;
use Test::Class::Most parent => 'Mason::Test::Class';
use Mason::Util qw(trim);
use HTTP::Request::Common;
use Plack::Test;

__PACKAGE__->default_plugins( [ '@Default', 'PSGIHandler' ] );

sub test_psgi_comp {
    my ( $self, %params ) = @_;
    my $interp = $self->interp;
    my $app    = sub { my $env = shift; $interp->handle_psgi($env) };
    my $path   = $params{path} or die "must pass path";
    my $qs     = $params{qs} || '';
    $self->add_comp( path => $path, src => $params{src} );
    test_psgi(
        $app,
        sub {
            my $cb  = shift;
            my $res = $cb->( GET( $path . $qs ) );
            if ( my $expect_content = $params{expect_content} ) {
                if ( ref($expect_content) eq 'Regexp' ) {
                    like( trim( $res->content ), $expect_content, "$path - content" );
                }
                else {
                    is( trim( $res->content ), trim($expect_content), "$path - content" );
                }
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

sub test_error : Tests(2) {
    my $self = shift;
    $self->test_psgi_comp(
        path           => '/die.m',
        src            => '% die "bleah";',
        expect_code    => 500,
        expect_content => qr/bleah at/,
    );
}

sub test_not_found : Tests(2) {
    my $self = shift;
    my $app = sub { my $env = shift; $self->interp->handle_psgi($env) };
    test_psgi(
        $app,
        sub {
            my $cb  = shift;
            my $res = $cb->( GET("/does/not/exist") );
            is( $res->code,    404, "status 404" );
            is( $res->content, '',  "blank content" );
        }
    );
}

sub test_args : Tests(2) {
    my $self = shift;
    $self->test_psgi_comp(
        path => '/args.m',
        qs   => '?a=1&a=2&b=3&b=4&c=5&c=6&d=7&d=8',
        src  => '
<%args>
$.a
$.b => (isa => "Int")
$.c => (isa => "ArrayRef");
$.d => (isa => "ArrayRef[Int]");
</%args>

a = <% $.a %>
b = <% $.b %>
c = <% join(",", @{$.c}) %>
d = <% join(",", @{$.d}) %>

% my $args = $.cmeta->args;
<% Mason::Util::dump_one_line($args) %>
',
        expect_content => <<EOF,
a = 2
b = 4
c = 5,6
d = 7,8

{a => '2',b => '4',c => ['5','6'],d => ['7','8']}
EOF
        expect_code => 200
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
