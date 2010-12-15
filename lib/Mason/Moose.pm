package Mason::Moose;
use MooseX::HasDefaults::RO   ();
use MooseX::StrictConstructor ();
use Moose::Exporter;
Moose::Exporter->setup_import_methods(
    also => [ 'MooseX::HasDefaults::RO', 'MooseX::StrictConstructor' ] );

1;
