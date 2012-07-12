package Mason::Test::Overrides::Component::StrictMoose;
use Moose::Exporter;
use MooseX::StrictConstructor ();
use base qw(Mason::Component::Moose);
use strict;
use warnings;

Moose::Exporter->setup_import_methods();

sub init_meta {
    my $class  = shift;
    my %params = @_;
    $class->SUPER::init_meta(@_);
    MooseX::StrictConstructor->import( { into => $params{for_class} } );
}

1;
