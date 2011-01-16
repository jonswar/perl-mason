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
    my $handler = sub {
        my $env = shift;
        $interp->handle_psgi($env);
    };

=head1 DESCRIPTION

Provides a L<PSGI|http://plackperl.org/> handler for Mason. It allows you to
use Mason on any web servers that support PSGI.

=head1 INTERP METHODS

=over

=item handle_psgi ($env)

Takes a PSGI environment hash and returns a standard PSGI response array.

A L<Mason::Plugin::PSGIHandler::PlackRequest> is constructed from the
environment, along with an empty L<Mason::Plugin::PSGIHandler::PlackResponse>. 
These are thin subclasses of L<Plack::Request> and L<Plack::Response>, and are
available within components via C<< $m->req >> and C<< $m->res >>.

The initial Mason path and parameters passed to C<< $interp->run() >> are taken
from the plack request methods C<< path_info() >> and C<< parameters() >>.

Your Mason components are responsible for setting the status and headers, by
calling C<< $m->res->status >> and C<< $m->res->headers >> or utility methods
that do so. C<< $m->clear_and_abort(status) >> is a convenient way to set a
status without a body, such as 404.

The Mason output becomes the plack response body; any value explicitly set in
C<< $m->res->body >> will be overwritten.

=back

=head1 REQUEST METHODS

=over

=item req ()

A reference to the L<Mason::Plugin::PSGIHandler::PlackRequest>.

    my $headers = $m->req->headers;
    my $cookie = $m->req->cookies->{'foo'};

=item res ()

A reference to the L<Mason::Plugin::PSGIHandler::PlackResponse>.

    $m->res->content_type('text/plain');
    $m->res->cookies->{foo} = { value => 123 };

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
