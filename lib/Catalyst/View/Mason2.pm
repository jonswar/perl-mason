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
        comp_root         => $c->config->{root},
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
    my $output = $self->render( $c, $path );

    unless ( $c->response->content_type ) {
        $c->response->content_type('text/html; charset=utf-8');
    }
    $c->response->body($output);

    return 1;
}

sub render {
    my ( $self, $c, $path, $args ) = @_;

    $self->interp->set_global( '$c' => $c );
    my %args = ( ref $args eq 'HASH' ? %$args : %{ $c->stash() } );
    return $self->interp->run( $path, %args )->output;
}

1;
