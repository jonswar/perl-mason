package Mason::Plugin::Cache::Interp;
use CHI;
use Mason::Util qw(catdir);
use Mason::PluginRole;

# Passed attributes
#
has 'cache_defaults'   => ( isa => 'HashRef', lazy_build => 1 );
has 'cache_root_class' => ( isa => 'Str', default => 'CHI' );

method _build_cache_defaults () {
    return {
        driver   => 'File',
        root_dir => catdir( $self->data_dir, 'cache' )
    };
}

1;
