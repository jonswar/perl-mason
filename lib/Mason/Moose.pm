package Mason::Moose;
use MooseX::HasDefaults::RO    ();
use MooseX::StrictConstructor  ();
use Method::Signatures::Simple ();
use namespace::autoclean       ();
use Moose::Exporter;
Moose::Exporter->setup_import_methods(
    also => [ 'MooseX::HasDefaults::RO', 'MooseX::StrictConstructor' ] );

sub init_meta {
    my ( $class, %params ) = @_;
    my $for_class = $params{for_class};
    Method::Signatures::Simple->import( into => $for_class );
    namespace::autoclean->import( -cleanee => $for_class );
    Moose->import( { into => $for_class } );
}

1;
