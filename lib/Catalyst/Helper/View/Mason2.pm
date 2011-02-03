package Catalyst::Helper::View::Mason2;

use strict;
use warnings;

our $VERSION = '0.01';

=head1 NAME

Catalyst::Helper::View::Mason2 - Helper for Mason 2.x Views

=head1 SYNOPSIS

    script/create.pl view Mason2 Mason2

=head1 DESCRIPTION

Helper for Mason 2.x Views.

=head2 METHODS

=head3 mk_compclass

=cut

sub mk_compclass {
    my ( $self, $helper ) = @_;
    my $file = $helper->{file};
    $helper->render_file( 'compclass', $file );
}

=head1 SEE ALSO

L<Catalyst::Manual>, L<Catalyst::Test>, L<Catalyst::Request>,
L<Catalyst::Response>, L<Catalyst::Helper>

=head1 AUTHOR

Jonathan Swartz <swartz@pobox.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify it under
the same terms as perl itself.

=cut

1;

__DATA__

__compclass__
package [% class %];

use strict;
use warnings;

use parent 'Catalyst::View::Mason2';

__PACKAGE__->config();

=head1 NAME

[% class %] - Mason 2.x View Component for [% app %]

=head1 DESCRIPTION

Mason View Component for [% app %]

=head1 SEE ALSO

L<[% app %]>, L<Mason>

=head1 AUTHOR

[% author %]

=head1 LICENSE

This library is free software . You can redistribute it and/or modify it under
the same terms as perl itself.

=cut

1;
