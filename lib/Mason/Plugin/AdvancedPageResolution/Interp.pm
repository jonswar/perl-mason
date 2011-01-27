package Mason::Plugin::AdvancedPageResolution::Interp;
use File::Basename;
use Mason::PluginRole;

# Passed attributes
#
has 'dhandler_names'         => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'index_names'            => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'no_autoextend_run_path' => ( isa => 'Bool',          default => 0 );
has 'page_extensions'        => ( isa => 'ArrayRef[Str]', default => sub { [ '.pm', '.m' ] } );

# Derived attributes
#
has 'ignore_file_regex'             => ( lazy_build => 1, init_arg => undef );
has 'resolve_page_component_method' => ( lazy_build => 1, init_arg => undef );

method _build_ignore_file_regex () {
    my $regex = '(/'
      . join( "|", @{ $self->autobase_names }, @{ $self->dhandler_names }, @{ $self->index_names } )
      . ')$';
    return qr/$regex/;
}

method _build_dhandler_names () {
    return [ map { "dhandler" . $_ } @{ $self->page_extensions } ];
}

method _build_index_names () {
    return [ map { "index" . $_ } @{ $self->page_extensions } ];
}

# Given /foo/bar.html, look for (by default):
#   /foo/bar.html.{pm,m},
#   /foo/bar/index.{pm,m},
#   /foo/bar/dhandler.{pm,m},
#   /foo.{pm,m}
#   /dhandler.{pm,m}
#
method _build_resolve_page_component_method ($interp:) {

    # Create a closure for efficiency - all this data is immutable for an interp.
    #
    my @dhandler_subpaths      = map { "/$_" } @{ $interp->dhandler_names };
    my $ignore_file_regex      = $interp->ignore_file_regex;
    my %is_dhandler_name       = map { ( $_, 1 ) } @{ $interp->dhandler_names };
    my $no_autoextend_run_path = $interp->no_autoextend_run_path;
    my @page_extensions        = @{ $interp->page_extensions };

    return sub {
        my ( $request, $path ) = @_;
        my $path_info      = '';
        my $declined_paths = $request->declined_paths;
        my @index_subpaths = map { "/$_" } @{ $interp->index_names };

        while (1) {
            my @candidate_paths =
                ( $path_info eq '' && $no_autoextend_run_path ) ? ($path)
              : ( $path eq '/' ) ? ( @index_subpaths, @dhandler_subpaths )
              : (
                ( grep { !/$ignore_file_regex/ } map { $path . $_ } @page_extensions ),
                ( map { $path . $_ } ( @index_subpaths, @dhandler_subpaths ) )
              );
            foreach my $candidate_path (@candidate_paths) {
                next if $declined_paths->{$candidate_path};
                my $compc = $interp->load($candidate_path);
                if ( defined($compc)
                    && ( $candidate_path =~ /$ignore_file_regex/ || $compc->cmeta->is_top_level ) )
                {
                    $request->{path_info} = $path_info;
                    return $compc
                      unless ( $path_info
                        && !$is_dhandler_name{ basename($candidate_path) }
                        && !$compc->allow_path_info );
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
