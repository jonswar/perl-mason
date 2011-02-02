package Mason::Plugin::ResolveURI;
use Moose;
with 'Mason::Plugin';

1;

# ABSTRACT: resolve URIs to page components
__END__

=head1 DESCRIPTION

This plugin maps URIs to top-level components. It provides default file
extensions for REST-style URIs and provides various ways to handle entire URI
hierarchies with a single component.

It is intended for those using Mason as the main controller in a web
application, e.g. with L<PSGIHandler|Mason::Plugin::PSGIHandler>. Those using
Mason as just a view layer of an MVC framework, or outside a web environment,
will probably not need this.

=head1 DETERMINING THE PAGE COMPONENT

Given the URI

    /news/sports/hockey

Mason searches for the following components in order, setting $m->path_info as
noted.

    /news/sports/hockey/index.{pm,m}
    /news/sports/hockey/dhandler.{pm,m}
    /news/sports/hockey.{pm,m}
    /news/sports/dhandler.{pm,m}  # $m->path_info = hockey
    /news/sports.{pm,m}           # $m->path_info = hockey (but see next section)
    /news/dhandler.{pm,m}         # $m->path_info = sports/hockey
    /news.{pm,m}                  # $m->path_info = sports/hockey (but see next section)
    /dhandler.{pm,m}              # $m->path_info = news/sports/hockey

The following sections describe these elements in more detail.

=head2 Dhandlers

A dhandler matches the URL of its directory as well as anything underneath.

    /news/sports/hockey/dhandler.{pm,m}
    /news/sports/dhandler.{pm,m}  # $m->path_info = hockey
    /news/dhandler.{pm,m}         # $m->path_info = sports/hockey
    /dhandler.{pm,m}              # $m->path_info = news/sports/hockey

=head2 Indexes

An index matches only the URL of its directory. It takes precedent over a
dhandler if both are present. It will never set C<< $m->path_info >>.

    /news/sports/hockey/index.{pm,m}

=head2 Autoextending path

By default, the URI is suffixed with ".m" and ".pm" to translate it to a
component path. This is useful for handling REST-style URIs.

    /news/sports/hockey.{pm,m}

=head2 Partial paths

A component can match an initial part of the URL, setting C<< $m->path_info >>
to the remainder:

    /news/sports.{pm,m}           # $m->path_info = hockey
    /news.{pm,m}                  # $m->path_info = sports/hockey

Since this isn't always desirable behavior, it must be explicitly enabled for
the component. Mason will call method C<allow_path_info> on the component
class, and will only allow the match if it returns true:

    %% method allow_path_info { 1 }

The default C<allow_path_info> returns false.

C<allow_path_info> is not checked on dhandlers, since the whole point of
dhandlers is to match partial paths.

=head1 ADDITIONAL INTERP PARAMETERS

=over

=item dhandler_names

Array reference of dhandler file names to check in order when resolving a
top-level path. Default is C<< ["dhandler.pm", "dhandler.m"] >>. An empty list
disables this feature.

=item index_names

Array reference of index file names to check in order when resolving a
top-level path. Default is C<< ["index.pm", "index.m"] >>. An empty list
disables this feature.

=item no_autoextend_uri

Do not automatically extend the URI with ".pm" and ".m" at the start of the
search.

=back

=head1 ADDITIONAL REQUEST METHODS

=over

=item decline ()

Clears the output buffer and issues the current request again, but acting as if
the previously chosen page component(s) do not exist.

For example, if the following components exist:

    /news/sports.m
    /news/dhandler.m
    /dhandler.m

then a request for path C</news/sports> will initially resolve to
C</news/sports.m>.  A call to C<< $m->decline >> would restart the request and
resolve to C</news/dhandler.m>, a second C<< $m->decline >> would resolve to
C</dhandler.m>, and a third would throw a "not found" error.

=item path_info ()

Returns the remainder of the top level path beyond the path of the page
component, with no leading slash. e.g. If a request for '/foo/bar/baz' resolves
to "/foo.m", the path_info is "bar/baz". Defaults to the empty string for an
exact match.

=back
