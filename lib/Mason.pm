package Mason;
use Mason::Interp;
use Mason::PluginManager;
use strict;
use warnings;

sub new {
    my ( $class, %params ) = @_;

    # Extract plugins and base_interp_class
    #
    my $plugin_specs      = delete( $params{plugins} )           || [];
    my $base_interp_class = delete( $params{base_interp_class} ) || 'Mason::Interp';

    # Process plugins and determine real interp_class
    #
    my @plugins = Mason::PluginManager->process_top_plugin_specs($plugin_specs);
    my $interp_class =
      Mason::PluginManager->apply_plugins_to_class( $base_interp_class, 'Interp', \@plugins );

    # Create and return interp
    #
    return $interp_class->new( mason_root_class => $class, plugins => \@plugins, %params );
}

1;

__END__

=pod

=head1 NAME

Mason - Powerful, high-performance templating for the web and beyond

=head1 SYNOPSIS

    % my $name = "Mason";
    Hello world! Welcome to <% $name %>.

=head1 DESCRIPTION

Mason is a powerful Perl-based templating system, designed to generate dynamic
content of all kinds.

Unlike many templating systems, Mason does not attempt to invent an alternate,
"easier" syntax for templates.  It provides a set of syntax and features
specific to template creation, but underneath it is still clearly and proudly
recognizable as Perl.

Mason is most often used for generating web pages. It can handle web requests
directly via PSGI, or act as the view layer for a web framework such as
Catalyst or Dancer.

All documentation is indexed at L<Mason::Manual>.

The previous major version of Mason (1.x) is available under the name
L<HTML::Mason>.

=head1 SUPPORT

The mailing list is L<mason-users@lists.sourceforge.net>. You must be
subscribed to send a message. To subscribe, visit
L<https://lists.sourceforge.net/lists/listinfo/mason-users>.

You can also visit us at C<#mason> on L<irc://irc.perl.org/#mason>.

Bugs and feature requests will be tracked at RT:

    http://rt.cpan.org/NoAuth/Bugs.html?Dist=Mason
    bug-mason@rt.cpan.org

The latest source code can be browsed and fetched at:

    http://github.com/jonswar/perl-mason
    git clone git://github.com/jonswar/perl-mason.git

The official Mason website is L<http://www.masonhq.com/>, however it contains
mostly information about L<Mason 1|HTML::Mason>. We're not sure what the future
of the website will be wrt Mason 2.

=head1 ACKNOWLEDGEMENTS

Thanks to Stevan Little and the L<Moose> team for the awesomeness of Moose,
which motivated me to create a second version of Mason years after I thought I
was done.

Thanks to Tatsuhiko Miyagawa and the L<PSGI/Plack|http://plackperl.org/> team
for giving the Perl web application world a massive shot of adrenaline.

=head1 SEE ALSO

L<HTML::Mason>

