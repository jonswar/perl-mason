package Mason::Component::InstanceMeta;
use Method::Signatures::Simple;
use Moose;
use Mason::Moose;
use strict;
use warnings;

# Passed attributes
has 'args'        => ( required => 1 );
has 'class_cmeta' => ( handles => [qw(dir_path is_external object_file path source_file)] );
has 'instance'    => ( required => 1, weak_ref => 1 );

# Derived attributes
has 'cache' => ( init_arg => undef, lazy_build => 1 );
has 'log' => ( init_arg => undef, lazy_build => 1 );

method _build_cache () {
    my $interp         = $self->instance->m->interp;
    my $chi_root_class = $interp->chi_root_class;
    Class::MOP::load_class($chi_root_class);
    my %options = ( %{ $interp->chi_default_params }, @_ );
    if ( !exists( $options{namespace} ) ) {
        $options{namespace} = $self->path;
    }
    return $chi_root_class->new(%options);
}

method _build_log () {
    my $log_category = "Mason::Component" . $self->path;
    $log_category =~ s/\//::/g;
    return Log::Any->get_logger( category => $log_category );
}

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
