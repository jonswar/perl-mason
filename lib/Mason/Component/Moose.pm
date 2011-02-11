package Mason::Component::Moose;
use Moose                      ();
use MooseX::HasDefaults::RW    ();
use Method::Signatures::Simple ();
use namespace::autoclean       ();
use Moose::Exporter;
use strict;
use warnings;
Moose::Exporter->setup_import_methods( also => ['Moose'] );

sub init_meta {
    my $class     = shift;
    my %params    = @_;
    my $for_class = $params{for_class};
    Method::Signatures::Simple->import( into => $for_class );
    namespace::autoclean->import( -cleanee => $for_class );
    MooseX::HasDefaults::RW->init_meta(@_);
    {
        no strict 'refs';
        *{ $for_class . '::CLASS' } = sub () { $for_class };    # like CLASS.pm
    }
}

1;

# ABSTRACT: Moose policies and exports for Mason components
__END__

=head1 DESCRIPTION

This module is automatically included in each generated Mason component class,
and is equivalent to

    use CLASS;
    use Moose;
    use MooseX::HasDefaults::RW;
    use Method::Signatures::Simple;
    use namespace::autoclean;

=head1 OVERRIDING

To override the default behavior, subclass this class and specify it as
C<base_component_moose_class> to L<Mason::Interp/Mason::Interp>.

For example, to use L<MooseX::StrictConstructor> in every component:

    package My::Mason::Component::Moose;
    use Moose::Exporter;
    use MooseX::StrictConstructor ();
    use strict;
    use warnings;
    use base qw(Mason::Component::Moose);

    sub init_meta {
        my $class = shift;
        $class->SUPER::init_meta(@_);
        MooseX::StrictConstructor->init_meta(@_);
    }

    ...

    my $interp = Mason::Interp->new(..., base_component_moose_class => 'My::Mason::Component::Moose');
