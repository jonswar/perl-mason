package Mason::t::Globals;

use Test::Class::Most parent => 'Mason::Test::Class';

sub test_globals : Tests {
    my $self = shift;
    $self->setup_interp( allow_globals => [qw(scalar $scalar2)] );
    my $interp = $self->interp;
    $interp->set_global( 'scalar',   5 );
    $interp->set_global( '$scalar2', 'vanilla' );
    throws_ok { $interp->set_global( '$bad', 8 ) } qr/\$bad is not in the allowed globals list/;
    $self->add_comp(
        path => '/values',
        src  => '
scalar = <% $scalar %>
$scalar2 = <% $scalar2 %>
',
    );
    $self->test_comp(
        src => '
<& /values &>
% $scalar++;
% $scalar2 .= "s";
<& /values &>
',
        expect => '
scalar = 5
$scalar2 = vanilla


scalar = 6
$scalar2 = vanillas
',
    );
}

1;
