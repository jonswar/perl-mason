package Mason::Request;
use autodie qw(:all);
use Log::Any qw($log);
use Moose;
use strict;
use warnings;

has 'buffer' => ( default  => '' );
has 'interp' => ( required => 1 );
has 'output' => ();

sub determine_request_component {
    my ( $self, $path ) = @_;

    my $request_comp_class = $self->interp->load($path);
    unless ($request_comp_class) {
        if ( $request_comp_class =
            $self->interp->find_comp_upwards( $path, $self->dhandler_name ) )
        {
            my $parent_path = $request_comp_class->dir_path;
            ( $self->{dhandler_arg} = $self->{top_path} ) =~
              s{^$parent_path/?}{};
            $log->debugf( "found dhandler '%s', dhandler_arg '%s'",
                $parent_path, $self->{dhandler_arg} )
              if $log->is_debug;
        }
    }

    return $request_comp_class;
}

sub exec {
    my $path      = shift;
    my $wantarray = wantarray();

    # Check the static_source touch file, if it exists, before the
    # first component is loaded.
    #
    $self->interp->check_static_source_touch_file();

    # Determine request component.
    #
    my $request_comp_class = $self->determine_request_component($path);
    unless ( defined($request_comp_class) ) {
        top_level_not_found_error(
            sprintf(
                "could not find component for initial path '%s' (component roots are: %s)",
                $path, $self->interp->comp_root_array_as_string()
            )
        );
    }
    my $request_comp = $request_comp_class->new(@_);

    $log->debugf( "starting request for '%s'", $request_comp_class->title )
      if $log->is_debug;

    my $retval;
    {
        local *SELECTED;
        tie *SELECTED, 'Tie::Handle::Mason';
        my $old = select SELECTED;
        scope_guard { select $old };

        $retval = eval { $self->enter_comp( $request_comp, 'render' ) };
        $err = $@;
    }
    die $err if $err && !$self->_aborted_or_declined($err);

    # If there's anything in the output buffer, send it to output().
    #
    if ( length( $self->{buffer} ) > 0 ) {
        $self->output->( $self->{buffer} );
    }

    # Return aborted value or result.
    #
    return
        $self->aborted($err)  ? $err->aborted_value
      : $self->declined($err) ? $err->declined_value
      :                         $retval;
}

sub clear_and_abort {
    my $self = shift;

    $self->clear_buffer;
    $self->abort(@_);
}

sub abort {
    my ( $self, $aborted_value ) = @_;
    Mason::Exception::Abort->throw(
        error         => 'Request->abort was called',
        aborted_value => $aborted_value
    );
}

#
# Determine whether $err (or $@ by default) is an Abort exception.
#
sub aborted {
    my ( $self, $err ) = @_;
    $err = $@ if !defined($err);
    return isa_mason_exception( $err, 'Abort' );
}

#
# Determine whether $err (or $@ by default) is an Decline exception.
#
sub declined {
    my ( $self, $err ) = @_;
    $err = $@ if !defined($err);
    return isa_mason_exception( $err, 'Decline' );
}

sub _aborted_or_declined {
    my ( $self, $err ) = @_;
    return $self->aborted($err) || $self->declined($err);
}

# Return a CHI cache object specific to this component.
#
sub cache {
    my ( $self, %options ) = @_;

    my $chi_root_class = $self->chi_root_class;
    load_class($chi_root_class);
    if ( !exists( $options{namespace} ) ) {
        $options{namespace} = $self->current_comp->comp_id;
    }
    if ( !exists( $options{driver} ) && !exists( $options{driver_class} ) ) {
        $options{driver} = 'File';
        $options{root_dir} ||= $self->interp->cache_dir;
    }
    return $chi_root_class->new(%options);
}

sub comp_exists {
    my ( $self, $path ) = @_;

    return $self->fetch_comp($path) ? 1 : 0;
}

sub decline {

    # TODO
}

sub fetch_comp {
    my ( $self, $path ) = @_;

    return undef unless defined($path);
    my $abs_path = (
        substr( $path, 0, 1 ) eq '/'
        ? $path
        : join( "/", $self->current_comp->comp_dir_path, $path )
    );

    # TODO: fetch_comp_cache
    my $canon_path = mason_canon_path($abs_path);
    my $comp_class = $self->interp->load($canon_path);
    return $comp_class;
}

sub print {
    my $self = shift;

    my $bufref = $self->{buffer};
    for ( @_ ) {
        $$bufref .= $_ if defined;
    }
}

# Execute the given component
#
sub comp {
    my $self = shift;

    my $path       = shift(@_);
    my $comp_class = $self->fetch_comp($path)
      or die "could not find component for path '$path'";
    my $comp = $comp_class->new(@_);

    $self->enter_comp( $comp_class, 'main', @_ );
}

# Like comp, but return component output.
#
sub scomp {
    my $self = shift;
    my $buf;
    local $self->{buffer} = \$buf;
    $self->comp(@_);
    return $buf;
}

sub enter_comp {
    my ( $self, $comp, $method ) = @_;

    local $self->{current_comp}          = $comp;
    local *{ $comp_class . "::m" }       = $self;
    local *{ $comp_class . "::_buffer" } = $self->{buffer};
    $comp->$method();
}

sub notes {
    my $self = shift;
    return $self->{notes} unless @_;

    my $key = shift;
    return $self->{notes}{$key} unless @_;

    return $self->{notes}{$key} = shift;
}

sub clear_buffer {
    my $self = shift;

    # TODO
}

sub flush_buffer {
    my $self = shift;

    $self->out_method->( $self->{request_buffer} )
      if length $self->{request_buffer};
    $self->{request_buffer} = '';
}

sub request_args {
    my ($self) = @_;
    if (wantarray) {
        return @{ $self->{request_args} };
    }
    else {
        return { @{ $self->{request_args} } };
    }
}

#
# Subroutine called by every component while in debug mode, convenient
# for breakpointing.
#
sub debug_hook {
    1;
}

sub log {
    my ($self) = @_;
    return $self->current_comp->comp_logger();
}

package Tie::Handle::Mason;

sub TIEHANDLE {
    my $class = shift;

    return bless {}, $class;
}

sub PRINT {
    my $self = shift;

    # TODO - why do we need to select STDOUT here?
    my $old = select STDOUT;

    # Use direct $m access instead of Request->instance() to optimize common case
    my $m = ${Mason::Commands::m};
    $m->print(@_);

    select $old;
}

sub PRINTF {
    my $self = shift;

    # apparently sprintf(@_) won't work, it needs to be a scalar
    # followed by a list
    $self->PRINT( sprintf( shift, @_ ) );
}

1;
