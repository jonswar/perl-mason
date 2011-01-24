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

=head2 Run path

The top-level run path is taken from the method L<Plack::Request/path>. So in a
simple Plack configuration like the one above, a URL like

    /foo/bar

would result in

    $interp->run("/foo/bar");

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

=head2 Run parameters

The top-level run parameters are taken from the method
L<Plack::Request/parameters>, which combines GET and POST parameters. So

    /foo/bar?a=5&b=6

would generally result in

    $interp->run("/foo/bar", a=>5, b=>6);

If there are multiple values for a parameter, generally only the last value
will be kept, as per L<Hash::MultiValue|Hash::MultiValue>. However, if the
corresponding attribute in the page component is declared an C<ArrayRef>, then
all values will be kept and passed in as an arrayref. For example, if the page
component C</foo/bar.m> has these declarations:

    <%args>
    $.a
    $.b => (isa => "Int")
    $.c => (isa => "ArrayRef");
    $.d => (isa => "ArrayRef[Int]");
    </%args>

then this URL

    /foo/bar?a=1&a=2&b=3&b=4&c=5&c=6&d=7&d=8

would result in

    $interp->run("/foo/bar", a=>2, b=>4, c=>[5,6], d => [7,8]);

You can always get the original Hash::MultiValue object from C<<
$m->request_args >>. e.g.

    my $hmv = $m->request_args;
    # get all values for 'e'
    $hmv->get_all('e');

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

If the top-level component path cannot be found, C<< $m->res->status >> is set
to 404. All other runtime errors fall through to be handled by Plack, i.e. with
L<Plack::Middleware::StackTrace|Plack::Middleware::StackTrace> in development
mode or a 500 error response in deployment mode.

=head1 INTERP METHODS

=over

=item handle_psgi ($env)

Takes a PSGI environment hash, calls an appropriate Mason request as detailed
above, and returns a standard PSGI response array.

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
