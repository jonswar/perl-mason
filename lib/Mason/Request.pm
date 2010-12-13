package Mason::Request;
use autodie qw(:all);
use Carp;
use File::Basename;
use Guard;
use Log::Any qw($log);
use Mason::TieHandle;
use Mason::Types;
use Method::Signatures::Simple;
use Moose;
use Mason::Moose;
use Scalar::Util qw(blessed);
use Try::Tiny;
use strict;
use warnings;

my $default_out = sub { print $_[0] };

# Passed attributes
has 'interp' => ( required => 1, weak_ref => 1 );
has 'out_method' =>
( isa => 'Mason::Types::OutMethod', default => sub { $default_out }, coerce => 1 );

# Derived attributes
has 'buffer_stack'       => ( init_arg => undef );
has 'count'              => ( init_arg => undef );
has 'path_info'          => ( init_arg => undef, default => '' );
has 'request_comp'       => ( init_arg => undef );
has 'request_code_cache' => ( init_arg => undef );

# Class attributes
our $current_request;
method current_request () { $current_request }

method BUILD ($params) {
    $self->push_buffer();
    $self->{request_code_cache} = {};
    $self->{count}              = $self->{interp}->request_count;
}

method run () {
    my $path      = shift;
    my $wantarray = wantarray();

    # Flush interp load cache
    #
    $self->interp->flush_load_cache();

    # Make this the current request.
    #
    local $current_request = $self;

    # Check the static_source touch file, if it exists, before the
    # first component is loaded.
    #
    $self->interp->check_static_source_touch_file();

    # Find request component class.
    #
    my ( $compc, $path_info ) = $self->top_level_path_to_component($path);
    $self->comp_not_found($path) if !defined($compc);
    $self->{path_info} = $path_info;

    my $request_comp = $compc->new( @_, 'm' => $self );
    $self->{request_comp} = $request_comp;
    $log->debugf( "starting request for '%s'", $request_comp->title )
      if $log->is_debug;

    # Flush interp load cache after request
    #
    scope_guard { $self->interp->flush_load_cache() };

    my ( $retval, $err );
    {
        local *TH;
        tie *TH, 'Mason::TieHandle';
        my $old = select TH;
        scope_guard { select $old };

        try {
            $retval = $request_comp->dispatch();
        }
        catch {
            $err = $_;
            die $err if !$self->aborted($err);
        };
    }

    # Send output to its final destination
    #
    $self->flush_buffer;

    # Return aborted value or result.
    #
    return $self->aborted($err) ? $err->aborted_value : $retval;
}

# Given /foo/bar, look for (by default):
#   /foo/bar.pm,  /foo/bar.m, /foo/bar/dhandler.pm, /foo/bar/dhandler.m
#   /foo.pm,      /foo.m,     /foo/dhandler.pm,     /foo/dhandler.m,
#   /dhandler.pm, /dhandler.m
#
method top_level_path_to_component ($path) {
    my $interp                  = $self->interp;
    my @dhandler_subpaths       = map { "/$_" } @{ $interp->dhandler_names };
    my @top_level_extensions    = @{ $interp->top_level_extensions };
    my $autohandler_or_dhandler = $interp->autohandler_or_dhandler_regex;
    my $path_info               = '';
    while (1) {
        my @candidates =
          ( $path eq '/' )
          ? @dhandler_subpaths
          : (
            ( grep { !/$autohandler_or_dhandler/ } map { $path . $_ } @top_level_extensions ),
            ( map { $path . $_ } @dhandler_subpaths )
          );
        foreach my $candidate (@candidates) {
            my $compc = $interp->load($candidate);
            if ( defined($compc) && $compc->comp_is_external ) {
                return ( $compc, $path_info );
            }
        }
        return () if $path eq '/';
        my $name = basename($path);
        $path_info = length($path_info) ? "$name/$path_info" : $name;
        $path = dirname($path);
    }
}

method clear_and_abort () {
    $self->clear_buffer;
    $self->abort(@_);
}

method abort ($aborted_value) {
    Mason::Exception::Abort->throw(
        error         => 'Request->abort was called',
        aborted_value => $aborted_value
    );
}

# Determine whether $err is an Abort exception.
#
method aborted ($err) {
    return blessed($err) && $err->isa('Mason::Exception::Abort');
}

# Determine current comp class based on caller() stack.
#
method current_comp_class () {
    my $cnt = 1;
    while (1) {
        if ( my $pkg = ( caller($cnt) )[0] ) {
            return $pkg if $pkg->isa('Mason::Component');
        }
        else {
            confess("cannot determine current_comp_class from stack");
        }
        $cnt++;
    }
}

# Return a CHI cache object specific to this component.
#
method cache () {
    my $chi_root_class = $self->interp->chi_root_class;
    load_class($chi_root_class);
    my %options = ( %{ $self->interp->chi_default_params }, @_ );
    if ( !exists( $options{namespace} ) ) {
        $options{namespace} = $self->current_comp_class->comp_id;
    }
    return $chi_root_class->new(%options);
}

method comp_exists ($path) {
    return $self->load($path) ? 1 : 0;
}

method decline () {

    # TODO
}

method fetch_compc ($path) {
    return undef unless defined($path);

    # Make absolute based on current component path
    #
    $path = join( "/", $self->current_comp_class->comp_dir_path, $path )
      unless substr( $path, 0, 1 ) eq '/';

    # Load the component class
    #
    my $compc = $self->interp->load($path)
      or return undef;

    return $compc;
}

method fetch_comp () {
    my $path  = shift;
    my $compc = $self->fetch_compc($path);
    return undef unless defined($compc);

    # Create and return a component instance
    #
    my $comp = $compc->new( @_, 'm' => $self );

    return $comp;
}

method fetch_comp_or_die () {
    my $comp = $self->fetch_comp(@_)
      or $self->comp_not_found( $_[0] );
    return $comp;
}

method comp_not_found ($path) {
    croak sprintf( "could not find component for path '%s' - component root is [%s]",
        $path, join( ", ", @{ $self->interp->comp_root } ) );
}

method print () {
    my $buffer = $self->current_buffer;
    for (@_) {
        $$buffer .= $_ if defined;
    }
}

# Execute the given component
#
method comp () {
    $self->fetch_comp_or_die(@_)->main();
}

# Like comp, but return component output.
#
method scomp () {
    $self->capture( \my $buf, sub { $self->comp(@_) } );
    return $buf;
}

method notes () {
    return $self->{notes}
      unless @_;
    my $key = shift;
    return $self->{notes}->{$key} unless @_;
    return $self->{notes}->{$key} = shift;
}

method clear_buffer () {
    foreach my $buffer ( $self->buffer_stack ) {
        $$buffer = '';
    }
}

method flush_buffer () {
    my $request_buffer = $self->request_buffer;
    $self->out_method->($$request_buffer)
      if length $$request_buffer;
    $$request_buffer = '';
}

method log () {
    return $self->current_comp_class->comp_logger();
}

# Buffer stack
#
method push_buffer () { my $s = ''; push( @{ $self->{buffer_stack} }, \$s ); }
method pop_buffer ()     { pop( @{ $self->{buffer_stack} } ) }
method request_buffer () { $self->{buffer_stack}->[0]; }
method current_buffer () { $self->{buffer_stack}->[-1] }

method capture ( $output_ref, $code ) {
    $self->push_buffer;
    scope_guard { $$output_ref = ${ $self->current_buffer }; $self->pop_buffer };
    $code->();
}

method apply_immediate_filter ( $filter_code, $code ) {
    $self->push_buffer;
    scope_guard {
        my $output = $filter_code->( ${ $self->current_buffer } );
        $self->pop_buffer;
        $self->print($output);
    };
    $code->();
}

1;

__END__

=head1 NAME

Mason::Request - Mason Request Class

=head1 SYNOPSIS

    $m->abort (...)
    $m->comp (...)
    etc.

=head1 DESCRIPTION

Mason::Request represents the current Mason request, and is the access point
for most Mason features not provided by syntactic tags.  Inside a component you
can access the current request object via the global C<$m>.  Outside of a
component, you can use the class method C<Mason::Request->current_request>.

=head1 COMPONENT PATHS

The methods L<Request-E<gt>comp|Mason::Request/item_comp>,
L<Request-E<gt>comp_exists|Mason::Request/item_comp_exists>, and
L<Request-E<gt>fetch_comp|Mason::Request/item_fetch_comp> take a component path
argument.  Component paths are like URL paths, and always use a forward slash
(/) as the separator, regardless of what your operating system uses.

If the path is absolute (starting with a '/'), then the component is found
relative to the component root. If the path is relative (no leading '/'), then
the component is found relative to the current component's directory.

=head1 PARAMETERS TO THE new() CONSTRUCTOR

=over

=item out_method

Indicates where to send the final page output. If out_method is a scalar
reference, output is appended to the scalar.  If out_method is a code
reference, the code is called with the output string. For example, to send
output to a file called "mason.out":

    open(my $fh, ">", "mason.out);
    ...
    out_method => sub { $fh->print($_[0]) }

By default, out_method prints to standard output.

=back

=head1 METHODS

=over

=item abort ([return value])

=for html <a name="item_abort"></a>

Ends the current request, finishing the page without returning through
components. The optional argument specifies the return value from
C<Interp::run>; in a web environment, this ultimately becomes the HTTP status
code.

C<abort> is implemented by throwing an Mason::Exception::Abort object and can
thus be caught by eval(). The C<aborted> method is a shortcut for determining
whether a caught error was generated by C<abort>.

=item clear_and_abort ([return value])

=for html <a name="item_clear_and_abort"></a>

This method is syntactic sugar for calling C<clear_buffer()> and then
C<abort()>.  If you are aborting the request because of an error, you will
often want to clear the buffer first so that any output generated up to that
point is not sent to the client.

=item aborted ([$err])

=for html <a name="item_aborted"></a>

Returns true or undef indicating whether the specified C<$err> was generated by
C<abort>. If no C<$err> was passed, uses C<$@>.

In this Try::Tiny code, we catch and process fatal errors while letting
C<abort> exceptions pass through:

    try {
        code_that_may_fail_or_abort()
    } catch {
        die $_ if $m->aborted($_);
        # handle fatal errors...
    };

=item cache

=for html <a name="item_cache"></a>

C<$m-E<gt>cache> returns a new L<CHI object|CHI> with a namespace specific to
this component. Any parameters are combined with
L<Interp/chi_default_parameters> and passed along to the
L<Interp/chi_root_class> constructor.

=item clear_buffer

=for html <a name="item_clear_buffer"></a>

Clears the Mason output buffer. Any output sent before this line is discarded.
Useful for handling error conditions that can only be detected in the middle of
a request.

clear_buffer is, of course, thwarted by L</flush_buffer>.

=item comp (comp, args...)

=for html <a name="item_comp"></a>

Calls the component designated by I<comp>. Any additional argumentss are passed
as attributes to the new component instance.

I<comp> may be an absolute or relative component path, in which case it will be
passed to L</fetch_comp>; or it may be a component class such as is returned by
L</fetch_comp>.

The <& &> tag provides a convenient shortcut for C<$m-E<gt>comp>.

=item comp_exists (path)

=for html <a name="item_comp_exists"></a>

Returns 1 if I<path> is the path of an existing component, 0 otherwise.

Depending on implementation, <comp_exists> may try to load the component
referred to by the path, and may throw an error if the component contains a
syntax error.

=item count

=for html <a name="item_count"></a>

Returns the number of this request, which is unique for a given request and
interpreter.

=item current_comp_class

=for html <a name="item_current_comp_class"></a>

Returns the current component class.

=item decline

=for html <a name="item_decline"></a>

Used from a top-level component or dhandler, this method clears the output
buffer, aborts the current request and restarts with the next applicable
component up the tree. If there are no more applicable components, throws a not
found error (same as if no applicable component had been found in the first
place)

=item path_info

=for html <a name="item_path_info"></a>

Returns the remainder of the top level path beyond the path of the page
component.

=item fetch_comp (comp_path)

=for html <a name="item_fetch_comp"></a>

Given a I<comp_path>, returns the corresponding component class or undef if no
such component exists.

=item flush_buffer

=for html <a name="item_flush_buffer"></a>

Flushes the Mason output buffer. Anything currently in the buffer is sent to
the request's L</out_method>.

Attempts to flush the buffers are ignored within the context of a call to C<<
$m->scomp >> or C<< $m->capture >>, or within a filter.

=item current_request

=for html <a name="item_current_request"></a>

This class method returns the C<Mason::Request> currently in use.  If called
when no Mason request is active it will return C<undef>.

=item interp

=for html <a name="item_interp"></a>

Returns the Interp object associated with this request.

=item log

=for html <a name="item_log"></a>

Returns a C<Log::Any> logger with a log category specific to the current
component.  The category for a component "/foo/bar" would be
"Mason::Component::foo::bar".

=item notes (key, value)

=for html <a name="notes"></a>

The C<notes()> method provides a place to store application data, giving
developers a way to share data among multiple components.  Any data stored here
persists for the duration of the request, i.e. the same lifetime as the Request
object.

Conceptually, C<notes()> contains a hash of key-value pairs. C<notes($key,
$value)> stores a new entry in this hash. C<notes($key)> returns a previously
stored value.  C<notes()> without any arguments returns a reference to the
entire hash of key-value pairs.

=item print (string)

=for html <a name="item_print"></a>

Add the given I<string> to the Mason output buffer. This happens implicitly for
all content placed in the main component body.

=item page

=for html <a name="item_page"></a>

Returns the page component originally called in the request.

=item scomp (comp, args...)

=for html <a name="item_scomp"></a>

Like L<comp|Mason::Request/item_comp>, but returns the component output as a
string instead of printing it. (Think sprintf versus printf.) The component's
return value is discarded.

=back

=head1 AUTHORS

Jonathan Swartz <swartz@pobox.com>

=head1 SEE ALSO

L<Mason|Mason>

=cut
