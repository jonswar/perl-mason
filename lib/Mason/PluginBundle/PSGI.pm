package Mason::PluginBundle::PSGI;
use Mason::PluginRole;
with 'Mason::PluginBundle';

sub requires_plugins { qw(AdvancedPageResolution HTMLFilters PSGIHandler) }

1;

# ABSTRACT: PSGI plugin bundle
__END__

=head1 INCLUDED PLUGINS

=over

=item L<AdvancedPageResolution|Mason::Plugin::AdvancedPageResolution>

=item L<HTMLFilters|Mason::Plugin::HTMLFilters>

=item L<PSGIHandler|Mason::Plugin::PSGIHandler>

=back

=head1 DESCRIPTION

A starter bundle for handling PSGI requests directly from Mason.

