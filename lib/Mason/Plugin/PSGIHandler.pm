package Mason::Plugin::PSGIHandler;
use Moose;
with 'Mason::Plugin';

1;

# ABSTRACT: PSGI handler for Mason
__END__

=head1 SYNOPSIS

    # app.psgi
    use Mason;
    my $interp = Mason->new(
         plugins => ['PSGIHandler', ...],
         comp_root => '/path/to/comp_root/',
         data_dir => '/path/to/data_dir/',
    );
    my $app = sub {
        my $env = shift;
        $interp->handle_psgi($env);
    };

=head1 DESCRIPTION

Provides a L<PSGI|http://plackperl.org/> handler for Mason. It allows Mason to
handle requests directly from any web servers that support PSGI.

=head2 Run path and parameters

The top-level run path and parameters are taken from the method
L<Plack::Request/path> and L<Plack::Request/parameters> respectively. So in a
simple Plack configuration like the one above, a URL like

    /foo/bar?a=5&b=6

would result in

    $interp->run("/foo/bar", a=>5, b=>6);

However, if you mounted your Mason app under "/mason",

    builder {
        mount "/mason" => builder {
            $app;
        };
        mount "/other" => $other_app;
        ...
    };

then the "/mason" portion of the URL would get stripped off in the top-level
run path.

=head2 Plack request object

A L<Mason::Plugin::PSGIHandler::PlackRequest> is constructed from the plack
environment and made available in C<< $m->req >>. This is a thin subclass of
L<Plack::Request> and provides information such as the URL and incoming HTTP
headers. e.g.

    my $headers = $m->req->headers;
    my $cookie = $m->req->cookies->{'foo'};

=head2 Plack response object

An empty L<Mason::Plugin::PSGIHandler::PlackResponse> is constructed and made
available in C<< $m->res >>. Your Mason components are responsible for setting
the status and headers, by calling C<< $m->res->status >> and C<<
$m->res->headers >> or utility methods that do so. e.g.

    $m->res->content_type('text/plain');
    $m->res->cookies->{foo} = { value => 123 };

    $m->redirect('http://www.google.com/', 301)  # sets header/status and aborts
    $m->clear_and_abort(404);   # sets status and aborts

If the Mason request finishes successfully, the Mason output becomes the plack
response body; any value explicitly set in C<< $m->res->body >> is ignored and
overwritten.  C<< $m->res->status >> is set to 200 if it hasn't already been
set.

If the Mason request dies with error, the error will be handled by Plack, i.e.
with L<Plack::Middleware::StackTrace|Plack::Middleware::StackTrace> in
development mode or a 500 error response in deployment mode.

=head1 INTERP METHODS

=over

=item handle_psgi ($env)

Takes a PSGI environment hash and returns a standard PSGI response array.

, along with an empty  These are thin subclasses of L<Plack::Request> and
L<Plack::Response>, and are available within components via C<< $m->req >> and
C<< $m->res >>.

The initial Mason path and parameters passed to C<< $interp->run() >> are taken
from the plack request methods C<< path_info() >> and C<< parameters() >>.


=back

=head1 REQUEST METHODS

=over

=item req ()

A reference to the L<Mason::Plugin::PSGIHandler::PlackRequest>.

=item res ()

A reference to the L<Mason::Plugin::PSGIHandler::PlackResponse>.

=item redirect (url[, status])

Sets headers and status for redirect, then clears the Mason buffer and aborts
the request. e.g.

    $m->redirect("http://somesite.com", 302);

is equivalent to

    $m->res->redirect("http://somesite.com", 302);
    $m->clear_and_abort();

=item abort (status)

=item clear_and_abort (status)

These methods are overriden to set the response status before aborting, if
I<status> is provided. e.g. to send back a NOT FOUND result:

    $m->clear_and_abort(404);

This is equivalent to

    $m->res->status(404);
    $m->clear_and_abort();

=back
