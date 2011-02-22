package Mason::Component::Import;
use strict;
use warnings;

sub import {
    my $class  = shift;
    my $caller = caller;
    $class->import_into($caller);
}

sub import_into {
    my ( $class, $for_class ) = @_;

    # no-op by default
}

1;

__END__

=pod

=head1 NAME

Mason::Component::Import - Extra component imports

=head1 DESCRIPTION

This module is automatically use'd in each generated Mason component class. It
imports nothing by default, but you can modify the C<import_into> method in
plugins to add imports.

