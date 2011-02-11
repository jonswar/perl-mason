package Mason::Moose;
use Moose                      ();
use MooseX::HasDefaults::RO    ();
use MooseX::StrictConstructor  ();
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
    Moose->init_meta(@_);
    MooseX::StrictConstructor->init_meta(@_);
    MooseX::HasDefaults::RO->init_meta(@_);
    {
        no strict 'refs';
        *{ $for_class . '::CLASS' } = sub () { $for_class };    # like CLASS.pm
    }
}

1;

# ABSTRACT: Mason Moose policies
__END__

=pod

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
    use namespace::autoclean;
