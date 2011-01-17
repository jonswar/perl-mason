package Mason::Plugin::AdvancedPageResolution::Request;
use File::Basename;
use Method::Signatures::Simple;
use Moose::Role;
use strict;
use warnings;

# Given /foo/bar, look for (by default):
#   /foo/bar.{pm,m},
#   /foo/bar/index.{pm,m},
#   /foo/bar/dhandler.{pm,m},
#   /foo.{pm,m}
#   /dhandler.{pm,m}
#
method resolve_page_component ($request_path) {
    my $interp               = $self->interp;
    my @dhandler_subpaths    = map { "/$_" } @{ $interp->dhandler_names };
    my @index_subpaths       = map { "/$_" } @{ $interp->index_names };
    my @page_extensions      = @{ $interp->page_extensions };
    my $autobase_or_dhandler = $interp->autobase_or_dhandler_regex;
    my $path                 = $request_path;
    my $path_info            = '';
    my $declined_paths       = $self->declined_paths;

    while (1) {
        my @candidate_paths =
            ( $path eq '/' )
          ? ( @index_subpaths, @dhandler_subpaths )
          : (
            ( grep { !/$autobase_or_dhandler/ } map { $path . $_ } @page_extensions ),
            ( map { $path . $_ } ( @index_subpaths, @dhandler_subpaths ) )
          );
        foreach my $candidate_path (@candidate_paths) {
            next if $declined_paths->{$candidate_path};
            my $compc = $interp->load($candidate_path);
            if ( defined($compc) && $compc->cmeta->is_external ) {
                $self->{path_info} = $path_info;
                return $compc;
            }
        }
        return undef if $path eq '/';
        my $name = basename($path);
        $path_info = length($path_info) ? "$name/$path_info" : $name;
        $path = dirname($path);
        @index_subpaths = ();    # only match in same directory
    }
}

1;
