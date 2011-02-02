package Mason::Plugin::ResolveURI::Interp;
use File::Basename;
use Mason::PluginRole;

# Passed attributes
#
has 'dhandler_names'         => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'index_names'            => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'no_autoextend_uri'      => ( isa => 'Bool',          default => 0 );
has 'page_extensions'        => ( isa => 'ArrayRef[Str]', default => sub { [ '.pm', '.m' ] } );

# Derived attributes
#
has 'resolve_uri_to_path' => ( lazy_build => 1, init_arg => undef );

method _build_dhandler_names () {
    return [ map { "dhandler" . $_ } @{ $self->page_extensions } ];
}

method _build_index_names () {
    return [ map { "index" . $_ } @{ $self->page_extensions } ];
}

# Given /foo/bar, look for (by default):
#   /foo/bar/index.{pm,m},
#   /foo/bar/dhandler.{pm,m},
#   /foo/bar.{pm,m},
#   /dhandler.{pm,m}
#   /foo.{pm,m}
#
method _build_resolve_uri_to_path ($interp:) {

    # Create a closure for efficiency - all this data is immutable for an interp.
    #
    my @dhandler_subpaths = map { "/$_" } @{ $interp->dhandler_names };
    my $regex = '(/'
      . join( "|",
        @{ $interp->autobase_names },
        @{ $interp->dhandler_names },
        @{ $interp->index_names } )
      . ')$';
    my $ignore_file_regex = qr/$regex/;
    my %is_dhandler_name  = map { ( $_, 1 ) } @{ $interp->dhandler_names };
    my $no_autoextend_uri = $interp->no_autoextend_uri;
    my @page_extensions   = @{ $interp->page_extensions };

    return sub {
        my ( $request, $uri ) = @_;
        my $path_info      = '';
        my $declined_paths = $request->declined_paths;
        my @index_subpaths = map { "/$_" } @{ $interp->index_names };
        my $path           = $uri;

        while (1) {
            my @candidate_paths =
                ( $path_info eq '' && $no_autoextend_uri ) ? ($path)
              : ( $path eq '/' ) ? ( @index_subpaths, @dhandler_subpaths )
              : (
                ( grep { !/$ignore_file_regex/ } map { $path . $_ } @page_extensions ),
                ( map { $path . $_ } ( @index_subpaths, @dhandler_subpaths ) )
              );
            foreach my $candidate_path (@candidate_paths) {
                next if $declined_paths->{$candidate_path};
                if ( my $compc = $interp->load($candidate_path) ) {
                    if (
                        ( $candidate_path =~ /$ignore_file_regex/ || $compc->cmeta->is_top_level )
                        && (   $path_info eq ''
                            || $compc->cmeta->is_dhandler
                            || $compc->allow_path_info )
                      )
                    {
                        $request->{path_info} = $path_info;
                        return $compc->cmeta->path;
                    }
                }
            }
            return undef if $path eq '/';
            my $name = basename($path);
            $path_info = length($path_info) ? "$name/$path_info" : $name;
            $path = dirname($path);
            @index_subpaths = ();    # only match index file in same directory
        }
    };
}

1;
