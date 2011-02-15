package Mason::Plugin::Cache;
use Moose;
with 'Mason::Plugin';

1;

__END__

=pod

=head1 NAME

Mason::Plugin::Cache - Provide a cache object to each component

=head1 SYNOPSIS

    my $result = $.cache->get('key');
    if (!defined($result)) {
        ... compute $result ...
        $.cache->set('key', $result, '5 minutes');
    }

    ...

    <% $.Cache('key2', '1 hour') { %>
      <!-- this will be cached for an hour -->
    </%>

=head1 DESCRIPTION

Adds a C<cache> method and C<Cache> filter to access a cache (L<CHI|CHI>)
object with a namespace unique to the component.

=head1 INTERP PARAMETERS

=over

=item cache_defaults

Hash of parameters passed to cache constructor. Defaults to

    driver=>'File', root_dir => 'DATA_DIR/cache'

which will create a basic file cache under Mason's L<data directory|data_dir>.

=item cache_root_class

Class used to create a cache. Defaults to L<CHI|CHI>.

=back

=head1 COMPONENT METHODS

=over

=item cache

Returns a new cache object with the namespace set to L<cache_namespace>.
Parameters to this method, if any, are combined with L<cache_defaults> and
passed to the L<cache_root_class> constructor.  The cache object is memoized
when no parameters are passed.

=item cache_namespace

The cache namespace to use. Defaults to the component's
L<path|Mason::Component::ClassMeta/path>.

=back

=head1 FILTERS

=over

=item Cache ($key, $set_options, [%cache_params])

Caches the content using C<< $self->cache >> and the supplied cache I<$key>.
I<$set_options>, if provided, is passed as the third argument to C<<
$self->cache->set >> - it is usually an expiration time. I<%cache_params>, if
any, are passed to C<< $self->cache >>.

    <% $.Cache($my_key, '1 hour') { %>
      <!-- this will be cached for an hour -->
    </%>

=back
