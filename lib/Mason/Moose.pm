package Mason::Moose;
use MooseX::HasDefaults::RO    ();
use MooseX::StrictConstructor  ();
use Method::Signatures::Simple ();
use Moose::Exporter;
Moose::Exporter->setup_import_methods(
    also => [ 'MooseX::HasDefaults::RO', 'MooseX::StrictConstructor' ] );

sub init_meta {
    my ( $class, %params ) = @_;
    Method::Signatures::Simple->import( into => $params{for_class} );
}

1;
