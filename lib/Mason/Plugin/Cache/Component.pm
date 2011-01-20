package Mason::Plugin::Cache::Component;
use Method::Signatures::Simple;
use Moose::Role;
use namespace::autoclean;

my %memoized;

sub cache_memoized {
    my $class = shift;
    if (@_) { $memoized{$class} = $_[0] }
    return $memoized{$class};
}

method cache_defaults ()   { $self->cmeta->interp->cache_defaults }
method cache_root_class () { $self->cmeta->interp->cache_root_class }
method cache_namespace ()  { $self->cmeta->path }

method cache () {
    if ( !@_ && $self->cache_memoized ) {
        return $self->cache_memoized;
    }
    my $cache_root_class = $self->cache_root_class;
    my %options = ( %{ $self->cache_defaults }, @_ );
    if ( !exists( $options{namespace} ) ) {
        $options{namespace} = $self->cache_namespace;
    }
    my $cache = $cache_root_class->new(%options);
    if ( !@_ ) {
        $self->cache_memoized($cache);
    }
    return $cache;
}

1;
