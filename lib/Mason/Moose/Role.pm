package Mason::Moose::Role;

use Moose::Role                ();
use Method::Signatures::Simple ();
use Moose::Exporter;
Moose::Exporter->setup_import_methods( also => ['Moose::Role'] );

sub init_meta {
    my $class     = shift;
    my %params    = @_;
    my $for_class = $params{for_class};
    Method::Signatures::Simple->import( into => $for_class );
    Moose::Role->init_meta(@_);
}

1;

__END__

=pod

=head1 NAME

Mason::Moose::Role - Mason Moose role policies

=head1 SYNOPSIS

    # instead of use Moose::Role;
    use Mason::Moose::Role;

=head1 DESCRIPTION

Sets certain Moose behaviors for Mason's internal roles. Using this module is
equivalent to

    use Moose::Role;
    use Method::Signatures::Simple;
