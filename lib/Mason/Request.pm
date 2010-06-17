package Mason::Request;
use autodie qw(:all);
use Guard;
use Log::Any qw($log);
use Mason::Request::TieHandle;
use Mason::Util qw(isa_mason_exception);
use Moose;
use strict;
use warnings;

# Passed attributes
has 'interp' => ( is => 'ro', required => 1, weak_ref => 1 );

# Derived attributes
has 'buffer_stack' => ( is => 'ro', init_arg => undef );
has 'request_comp' => ( is => 'ro', init_arg => undef );

# Class attributes
our $current_request;
sub current_request { $current_request }

sub BUILD {
    my ( $self, $params ) = @_;
    $self->push_buffer();
}

sub run {
    my $self      = shift;
    my $path      = shift;
    my $wantarray = wantarray();

    # Make this the current request.
    #
    local $current_request = $self;

    # Check the static_source touch file, if it exists, before the
    # first component is loaded.
    #
    $self->interp->check_static_source_touch_file();

    # Fetch request component.
    #
    my $request_comp = $self->fetch_comp_or_die( $path, @_ );
    $self->{request_comp} = $request_comp;
    $log->debugf( "starting request for '%s'", $request_comp->title )
      if $log->is_debug;

    my ( $retval, $err );
    {
        local *TH;
        tie *TH, 'Mason::Request::TieHandle';
        my $old = select TH;
        scope_guard { select $old };

        $retval = eval { $request_comp->render() };
        $err = $@;
    }
    die $err if $err && !$self->_aborted_or_declined($err);

    $self->flush_buffer;

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

    my $chi_root_class = $self->interp->chi_root_class;
    load_class($chi_root_class);
    if ( !exists( $options{namespace} ) ) {
        $options{namespace} = $self->current_comp->comp_id;
    }
    if ( !exists( $options{driver} ) && !exists( $options{driver_class} ) ) {
        $options{driver} = 'File';
        $options{root_dir} ||= catdir( $self->interp->data_dir, "cache" );
    }
    return $chi_root_class->new(%options);
}

sub comp_exists {
    my ( $self, $path ) = @_;

    return $self->load($path) ? 1 : 0;
}

sub decline {

    # TODO
}

sub fetch_comp {
    my $self = shift;
    my $path = shift;

    return undef unless defined($path);

    # Make absolute based on current component path
    #
    $path = join( "/", $self->current_comp->comp_dir_path, $path )
      unless substr( $path, 0, 1 ) eq '/';

    my $compc = $self->interp->load($path);
    my $comp = $compc->new( @_, comp_request => $self );

    return $comp;
}

sub fetch_comp_or_die {
    my $self = shift;
    my $comp = $self->fetch_comp(@_)
      or die "could not find component for path '$_[0]'";
    return $comp;
}

sub print {
    my $self = shift;

    my $buffer = $self->{current_buffer};
    for (@_) {
        $buffer .= $_ if defined;
    }
}

# Execute the given component
#
sub comp {
    my $self = shift;

    $self->fetch_comp_or_die(@_)->main();
}

# Like comp, but return component output.
#
sub scomp {
    my $self = shift;
    my ($buf) = $self->capture( sub { $self->comp(@_) } );
    return $buf;
}

sub notes {
    my $self = shift;
    return $self->{notes} unless @_;
    my $key = shift;
    return $self->{notes}->{$key} unless @_;
    return $self->{notes}->{$key} = shift;
}

sub clear_buffer {
    my $self = shift;
    foreach my $buffer ( $self->buffer_stack ) {
        $$buffer = '';
    }
}

sub flush_buffer {
    my $self = shift;

    my $request_buffer = $self->request_buffer;
    $self->interp->out_method->($$request_buffer)
      if length $$request_buffer;
    $$request_buffer = '';
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

# Buffer stack
#
sub push_buffer { my $s = ''; push( @{ $_[0]->{buffer_stack} }, \$s ) }
sub pop_buffer { pop( @{ $_[0]->{buffer_stack} } ) }
sub request_buffer { $_[0]->{buffer_stack}->[0] }
sub current_buffer { $_[0]->{buffer_stack}->[-1] }

sub capture {
    my ( $self, $code ) = @_;
    $self->push_buffer;
    scope_guard { $self->pop_buffer };
    return $code->();
}

1;
