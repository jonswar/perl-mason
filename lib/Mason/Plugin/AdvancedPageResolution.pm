package Mason::Plugin::AdvancedPageResolution;
use Moose;
with 'Mason::Plugin';

1;

# ABSTRACT: advanced resolution of request paths to page components
__END__

=head1 DESCRIPTION

This plugin enhances the way that top-level paths are mapped to page
components. It provides default file extensions for REST-style URLs and
provides various ways to handle entire path hierarchies with a single
component.

It is intended for those using Mason as the main controller in a web
application. Those using Mason as just a view layer of an MVC framework, or
outside a web environment, will probably not need this.

=head1 DETERMINING THE PAGE COMPONENT

Given a top-level request path, Mason generates a number of candidate component
paths, searching in order until one is found:

=over

=item *

The requested path itself suffixed with ".pm" or ".m" (or just the requested
path itself if L</no_autoextend_run_path> is on)

=item *

"index.pm" or "index.m" under the requested path

=item *

"dhandler.pm" or "dhandler.m" under the requested path

=back

If it cannot find any of these, then Mason scans backwards through the path,
checking each directory upwards for the same set of files B<except> for
"index.*". In this case it sets C<< $m->path_info >> to the unmatched latter
part of the path.

For example, given the path

    /news/sports/hockey

Mason searches for the following components in order, setting $m->path_info as
noted.

    /news/sports/hockey.{pm,m}
    /news/sports/hockey/index.{pm,m}
    /news/sports/hockey/dhandler.{pm,m}
    /news/sports.{pm,m}           # $m->path_info = hockey (but see next section)
    /news/sports/dhandler.{pm,m}  # $m->path_info = hockey
    /news.{pm,m}                  # $m->path_info = sports/hockey (but see next section)
    /news/dhandler.{pm,m}         # $m->path_info = sports/hockey
    /dhandler.{pm,m}              # $m->path_info = news/sports/hockey

A component or dhandler that does not want to handle a particular request may
call L</decline>, in which case Mason continues down the list of possibilities.

Note that the bare request path itself (in this case C<< /news/sports/hockey
>>) is not one of the components searched for. You can add the empty string
("") to L</page_extensions> to change this.

=head2 Accepting or rejecting partial match

When a partial path matches on a non-dhandler component, e.g. these cases from
above:

    /news/sports.{pm,m}           # $m->path_info = hockey
    /news.{pm,m}                  # $m->path_info = sports/hockey

the component may not want to accept the match. In many cases you'll only want
a component to match its exact URL.

Mason checks this by calling the method C<< accept_path_info >> on the
component with the path_info as a parameter.  If it returns a true value, the
match is accepted; otherwise it is as if you have called L</decline>, and Mason
continues down the list of possibilities.

By default C<accept_path_info> returns B<false>, so you will have to explicitly
indicate that you want to accept a partial match. You can accept any path_info:

    %% method accept_path_info { 1 }

Or you can use this opportunity to parse the path_info into attributes and make
sure it's acceptable. Here's an example that looks for a path_info of the form
YYYY/MM (it requires the L<LValueAttribute
plugin|Mason::Plugin::LValueAttribute>).

    <%shared>
    $.month
    $.year
    </%shared>

    <%class>
    method accept_path_info ($path_info) {
        ($.year, $.month) = ($path_info =~ m|^(\d{4})/(\d{2})$|);
        return $.year && $.month && $.month <= 12;
    }
    </%class>

You can put this in a top-level L<Base.pm> if you want to accept path_info by
default for all components:

    method accept_path_info { 1 }

Even if C<accept_path_info> returns true, the component can still decide to
L</decline> later.

Mason does not check C<accept_path_info> on dhandlers, since their very reason
for existing is to match partial paths.

=head1 ADDITIONAL INTERP PARAMETERS

=over

=item dhandler_names

Array reference of dhandler file names to check in order when resolving a
top-level path. Default is C<< ["dhandler.pm", "dhandler.m"] >>. See
L<Mason::Manual/Determining the page component>.

=item index_names

Array reference of index file names to check in order when resolving a
top-level path (only in the bottom-most directory). Default is C<< ["index.pm",
"index.m"] >>. See L<Mason::Manual/Determining the page component>.

=item no_autoextend_run_path

Do not automatically extend the run path with ".pm" and ".m" at the start of
the search. Does not affect dhandler or index names.

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
