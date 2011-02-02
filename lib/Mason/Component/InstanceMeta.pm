package Mason::Component::InstanceMeta;
use Mason::Component::ClassMeta;
use Mason::Moose;

# Passed attributes
has 'args'        => ( required => 1 );
has 'class_cmeta' => ( isa => 'Mason::Component::ClassMeta', handles => qr/^(?!args)/ );
has 'instance'    => ( required => 1, weak_ref => 1 );

__PACKAGE__->meta->make_immutable();

1;

# ABSTRACT: Meta-information about Mason component instance
__END__

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

The full hashref of arguments that was passed to the component's constructor.

=back

=head1 SEE ALSO

L<Mason|Mason>

=cut
