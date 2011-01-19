package Mason::Plugin::Globals;
use Moose;
with 'Mason::Plugin';

1;

# ABSTRACT: Component-wide globals
__END__

=head1 SYNOPSIS

    my $interp = Mason->new (
       plugins => ['Globals'],
       allow_globals => [qw($scalar @list)],
       ...
    );

    $interp->set_global('$scalar', 5);
    $interp->set_global('@list', 5, 6, 7);

    ...

    # In any component:
    scalar = <% $scalar %>
    list = <% join(", ", @list) %>

=head1 DESCRIPTION

Allows you to create global variables accessible from all components (like C<<
$m >>).

As in any programming environment, globals should be created sparingly (if at
all) and only when other mechanisms (parameter passing, attributes, singletons)
will not suffice.

The Mason Catalyst view, for example, creates a C<< $c >> global set to the
context object in each request.

=head1 INTERP PARAMETERS

=over

=item allow_globals (varnames)

List of one or more global variable names allowed in components. Each name may
have a sigil ($, @, %) or no sigil, which indicates a scalar.

    allow_globals => [qw(scalar $scalar2 @list %hash)]

=item globals_package

Package in which globals are actually kept. Defaults to 'MG' plus the
interpreter's count, e.g. 'MG0'.

=back

=head1 INTERP METHODS

=over

=item set_global (varname, value/values)

Set the global I<varname> to I<value> (for a scalar) or I<values> (for a list
or hash).

    $interp->set_global('scalar', 5);
    $interp->set_global('$scalar2', $some_object);
    $interp->set_global('@list', 5, 6, 7);
    $interp->set_global('%hash', foo=>5, bar=>6);

This is equivalent to the following within any component (assuming that these
are all on the allowed globals list):

    $scalar = 5;
    $scalar2 = $some_object;
    @list = (5, 6, 7);
    %hash = (foo=>5, bar=>6);

=back
