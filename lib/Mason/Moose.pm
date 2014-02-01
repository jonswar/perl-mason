package Mason::Moose;    ## no critic (Moose::RequireMakeImmutable)

use Moose                      ();
use MooseX::HasDefaults::RO    ();
use MooseX::StrictConstructor  ();
use Method::Signatures::Simple ();
use Moose::Exporter;
use strict;
use warnings;
Moose::Exporter->setup_import_methods( also => ['Moose'] );

sub init_meta {
    my $class     = shift;
    my %params    = @_;
    my $for_class = $params{for_class};
    Method::Signatures::Simple->import( into => $for_class );
    Moose->init_meta(@_);
    MooseX::StrictConstructor->import( { into => $for_class } );
    MooseX::HasDefaults::RO->import( { into => $for_class } );
    {
        no strict 'refs';
        *{ $for_class . '::CLASS' } = sub () { $for_class };    # like CLASS.pm
    }
}

1;

__END__

=pod

=head1 NAME

Mason::Moose - Mason Moose policies

=head1 SYNOPSIS

    # instead of use Moose;
    use Mason::Moose;

=head1 DESCRIPTION

Sets certain Moose behaviors for Mason's internal classes. Using this module is
equivalent to

    use CLASS;
    use Moose;
    use MooseX::HasDefaults::RO;
    use MooseX::StrictConstructor;
    use Method::Signatures::Simple;
