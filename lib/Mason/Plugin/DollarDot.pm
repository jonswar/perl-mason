package Mason::Plugin::DollarDot;
use Moose;
with 'Mason::Plugin';

__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

Mason::Plugin::DollarDot - Allow $. as substitution for $self-> and in
attribute names

=head1 SYNOPSIS

    <%class>
    has 'name';
    has 'date';
    </%class>

    <%method greet>
    Hello, <% $.name %>. Today is <% $.date %>.
    </%method>

    ...
    % $.greet();

    <%init>
    # Set the date
    $.date(scalar(localtime));
    # or, if combined with LvalueAttributes
    $.date = scalar(localtime);
    </%init>

=head1 DESCRIPTION

This plugin substitutes C<< $.I<identifier> >> for C<< $self->I<identifier> >>
in all Perl code inside components, so that C<< $. >> can be used when
referring to attributes and calling methods. The actual regex is

    s/ \$\.([^\W\d]\w*) / \$self->$1 /gx;

=head1 RATIONALE

In Mason 2, components have to write C<< $self-> >> a lot to refer to
attributes that were simple scalars in Mason 1. This eases the transition pain.
C<< $. >> was chosen because of its similar use in Perl 6.

This plugin falls under the heading of gratuitous source filtering, which the
author generally agrees is Evil. That said, this is a very limited filter, and
seems unlikely to break any legitimate Perl syntax other than use of the C<< $.
>> special variable (input line number).

=head1 BUGS

Will not interpolate as expected inside double quotes:

    "My name is $.name"   # nope

instead you have to do

    "My name is " . $.name
