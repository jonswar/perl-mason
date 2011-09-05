package Mason::t::DollarDot;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_dollardot : Tests {
    my $self = shift;
    $self->add_comp(
        path => '/helper.mi',
        src  => '<%class>has "foo";</%class>
Helper: <% $.foo %>
',
    );
    $self->test_comp(
        src => '
<%class>
has "name" => ( default => "Joe" );

</%class>

<%class>
has "compname";
has "date";
</%class>

<%method greet>
Hello, <% $.name %>. Today is <% $.date %>.
</%method>

% $.greet();

<& $.compname, foo => $.date &>
<& /helper.mi, foo => $.name &>

<%init>
$.date("March 5th");
$.compname("helper.mi");
</%init>
',
        expect => '
Hello, Joe. Today is March 5th.

Helper: March 5th

Helper: Joe
',
    );
}

1;
