package Mason::Moose;
use MooseX::HasDefaults::RO ();
use Moose::Exporter;
Moose::Exporter->setup_import_methods( also => ['MooseX::HasDefaults::RO'] );

1;
