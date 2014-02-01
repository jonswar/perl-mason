package Mason::t::LvalueAttributes;

use Test::Class::Most parent => 'Mason::Test::Class';

__PACKAGE__->default_plugins( [ '@Default', 'LvalueAttributes' ] );

sub test_lvalue : Tests {
    my $self = shift;
    $self->test_comp(
        src => '
<%class>
has "a" => (is => "rw");
has "b" => (is => "ro");

</%class>

<%init>
$.a = 5;
print "a = " . $.a . "\n";
$.a(6);
print "a = " . $.a . "\n";
eval { $.b = 6 };
print $@ . "\n";
</%init>
',
        expect => qr/a = 5\na = 6\nCan't modify.*/,
    );
}

1;
