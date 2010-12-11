package Mason::Moose;
use Moose                     ();
use MooseX::HasDefaults::RO   ();
use MooseX::StrictConstructor ();
use Moose::Exporter;
Moose::Exporter->setup_import_methods( also => ['MooseX::HasDefaults::RO'] );

1;
