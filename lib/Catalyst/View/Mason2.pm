package Catalyst::View::Mason2;
use Mason;
use MRO::Compat;
use Scalar::Util qw/blessed/;
use strict;
use warnings;
use base qw(Catalyst::View);

__PACKAGE__->mk_accessors(qw(default_extension interp));

sub new {
    my ( $class, $c, $arguments ) = @_;

    my %config = (
        comp_root         => $c->path_to( 'root', 'comps' ),
        mason_root_class  => 'Mason',
        plugins           => [],
        default_extension => '.m',
        %{ $class->config },
        %{$arguments},
    );

    # Stringify comp_root and data_dir if they are objects
    #
    foreach my $key (qw(comp_root data_dir)) {
        $config{$key} .= "" if blessed( $config{$key} );
    }

    # Add necessary plugins and globals
    #
    push( @{ $config{plugins} },       'Globals' );
    push( @{ $config{allow_globals} }, '$c' );

    # Call superclass to create initial object
    #
    my $self = $class->next::method( $c, \%config );
    $self->config( {%config} );

    # Remove non-Mason parameters.
    #
    my $mason_root_class = delete( $config{mason_root_class} );
    delete @config{qw(catalyst_component_name default_extension)};

    # Create and store the interp
    #
    my $interp = $mason_root_class->new(%config);
    $self->interp($interp);

    return $self;
}

sub get_component_path {
    my ( $self, $c ) = @_;

    # If template was specified in stash, use that; otherwise use the action
    # with default extension (if any) appended.
    #
    my $path = $c->stash->{template} || $c->action . $self->default_extension;
    $path = "/$path" if substr( $path, 0, 1 ) ne '/';

    return $path;
}

sub process {
    my ( $self, $c ) = @_;

    my $path = $self->get_component_path($c);
    my $output = $self->render( $c, $path, $c->stash );

    unless ( $c->response->content_type ) {
        $c->response->content_type('text/html; charset=utf-8');
    }
    $c->response->body($output);

    return 1;
}

sub render {
    my ( $self, $c, $path, $args ) = @_;

    $self->interp->set_global( '$c' => $c );
    return $self->interp->run( $path, %$args )->output;
}

1;

# ABSTRACT: Mason 2.0 View Class
__END__

=head1 SYNOPSIS

    # use the helper
    script/create.pl view Mason2 Mason2

    # lib/MyApp/View/Mason2.pm
    package MyApp::View::Mason2;

    use base 'Catalyst::View::Mason2';

    __PACKAGE__->config(
        # insert Mason parameters here
    );

    1;

    $c->forward('MyApp::View::Mason');

=head1 DESCRIPTION

Allows you to use L<Mason 2.x|Mason> for your views.

=head1 EXAMPLE

From the Catalyst controller:

    $c->stash->{name} = 'Homer'; # Pass a scalar
    $c->stash->{extra_info} = {
               last_name => 'Simpson',
               children => [qw(Bart Lisa Maggie)]
    }; # A ref works too

From the Mason template:

    <%args>
    $.name
    $.extra_info
    </%args>
    <p>Your name is <strong><% $.name %> <% $.extra_info->{last_name} %></strong>
    <p>Your children are:
    <ul>
    % foreach my $child (@{$.extra_info->{children}}) {
    <li><% $.child %></li>
    % }
    </ul>

=head1 VIEW CONFIGURATION

=over

=item default_extension

Extension to add to C<< $c->action >> to form the initial component path when
C<< $c->stash->{template} >> has not been provided. Defaults to ".m", so for an
action '/foo/bar', the initial component path will be '/foo/bar.m'.

May be set to the empty string if you don't want any extension added.

=item mason_root_class

Class to use for creating the Mason object. Defaults to 'Mason'.

=back

=head1 MASON CONSTRUCTOR

Other than the special keys above, the configuration for this view will be
passed directly into C<< Mason->new >>.

There are a few defaults specific to this view:

=over

=item comp_root

If not provided, defaults C<< $c->path_to('root', 'comps') >>.

=item data_dir

If not provided, defaults C<< $c->path_to('data') >>.

=item allow_globals

Automatically includes C<$c>, the Catalyst context.

=item plugins

Automatically includes L<Global|Mason::Plugin::Global>, for setting C<$c>.

=back

All other defaults are standard Mason.

=head1 GLOBALS

All components have access to C<$c>, the Catalyst context.

=head1 METHODS

=over

=item process ($c)

Renders the component specified in C<< $c->stash->{template} >> or, if not
specified, C<< $c->action >> appended with L</default_extension>.

The component path is prefixed with a '/' if it does not already have one.

Request arguments are taken from C<< $c->stash >>.

=item render ($c, $path, \%args)

Renders the component I<$path> with I<\%args>, and returns the output.

=back

=cut
