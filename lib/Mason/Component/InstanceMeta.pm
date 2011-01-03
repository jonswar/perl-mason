package Mason::Component::InstanceMeta;
use Moose;
use Mason::Moose;
use strict;
use warnings;

# Passed attributes
has 'args'        => ( required => 1 );
has 'class_cmeta' => ( handles => [qw(cache dir_path is_external log object_file path source_file)] );
has 'instance'    => ( required => 1, weak_ref => 1 );

1;

__END__

=head1 NAME

Mason::Component::InstanceMeta - Meta-information about Mason component
instance

=head1 SYNOPSIS

    # In a component:
    My path is <% $.cmeta->path %>
    My source file is <% $.cmeta->source_file %>
    I was called with args <% join(", ", %{$.cmeta->args}) %>

=head1 DESCRIPTION

Provides everything that
L<Mason::Component::ClassMeta|Mason::Component::ClassMeta> does, plus extra
information only available for component instances.

=over

=item args

The full hashref of attributes that the component was created with.

=back

=head1 SEE ALSO

L<Mason|Mason>

=cut
