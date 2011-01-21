package Mason::t::Globals;
use Test::Class::Most parent => 'Mason::Test::Class';

__PACKAGE__->default_plugins( [ '@Default', 'Globals' ] );

sub test_globals : Tests(2) {
    my $self = shift;
    $self->setup_interp( allow_globals => [qw(scalar $scalar2 @list %hash)] );
    my $interp = $self->interp;
    $interp->set_global( 'scalar',   5 );
    $interp->set_global( '$scalar2', 'vanilla' );
    $interp->set_global( '@list',    5, 6, 7 );
    $interp->set_global( '%hash',    foo => 5, bar => 6 );
    throws_ok { $interp->set_global( '$bad', 8 ) } qr/\$bad is not in the allowed globals list/;
    $self->add_comp(
        path => '/values',
        src  => '
scalar = <% $scalar %>
$scalar2 = <% $scalar2 %>
@list = <% join(", ", @list) %>
 %hash = <% Mason::Util::dump_one_line(\%hash) %>
',
    );
    $self->test_comp(
        src => '
<& /values &>
% $scalar++;
% $scalar2 .= "s";
% push(@list, 8);
% $hash{baz} = 7;
<& /values &>
',
        expect => '
scalar = 5
$scalar2 = vanilla
@list = 5, 6, 7
 %hash = {bar => 6,foo => 5}


scalar = 6
$scalar2 = vanillas
@list = 5, 6, 7, 8
 %hash = {bar => 6,baz => 7,foo => 5}
',
    );
}

1;
