package Mason::t::Globals;

use Test::Class::Most parent => 'Mason::Test::Class';

sub test_globals : Tests {
    my $self = shift;

    throws_ok {
        $self->setup_interp( allow_globals => [qw( @array )] );
    } qr/only scalar globals supported/;

    throws_ok {
        $self->setup_interp( allow_globals => [qw( %hash )] );
    } qr/only scalar globals supported/;

    $self->setup_interp( allow_globals => [qw(scalar $scalar2 $scalar3 )] );
    my $interp = $self->interp;

    throws_ok { $interp->set_global( '$bad', 8 ) } qr/\$bad is not in the allowed globals list/;
    throws_ok { $interp->set_global( 'scalar' ) } qr/set_global expects a var name and value/;
    throws_ok { $interp->set_global( 'scalar', 1, 2 ) } qr/set_global only supports scalars/;

    lives_ok  { $interp->set_global( '$scalar3', 'This value should vanish' ) };
    lives_ok  { $interp->set_global( '$scalar3', undef ) };

    $interp->set_global( 'scalar',   5 );
    $interp->set_global( '$scalar2', 'vanilla' );

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
% die q($scalar3 should not be defined) if defined $scalar3;
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
