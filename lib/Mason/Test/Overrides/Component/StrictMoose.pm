package Mason::Test::Overrides::Component::StrictMoose;
use Moose::Exporter;
use MooseX::StrictConstructor ();
use strict;
use warnings;
use base qw(Mason::Component::Moose);
Moose::Exporter->setup_import_methods();

sub init_meta {
    my $class  = shift;
    my %params = @_;
    $class->SUPER::init_meta(@_);
    MooseX::StrictConstructor->import( { into => $params{for_class} } );
}

1;
