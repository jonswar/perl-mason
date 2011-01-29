package Mason::Request;
use autodie qw(:all);
use Carp;
use File::Basename;
use Guard;
use Log::Any qw($log);
use Mason::Exceptions;
use Mason::TieHandle;
use Mason::Types;
use Mason::Moose;
use Scalar::Util qw(blessed reftype);
use Try::Tiny;

my $default_out = sub { my ( $text, $self ) = @_; $self->{output} .= $text };

# Passed attributes
#
has 'interp'         => ( required => 1, weak_ref => 1 );
has 'out_method'     => ( isa => 'Mason::Types::OutMethod', default => sub { $default_out }, coerce => 1 );

# Derived attributes
#
has 'buffer_stack'       => ( init_arg => undef );
has 'count'              => ( init_arg => undef );
has 'go_result'          => ( init_arg => undef );
has 'output'             => ( init_arg => undef, default => '' );
has 'page'               => ( init_arg => undef );
has 'request_args'       => ( init_arg => undef );
has 'request_code_cache' => ( init_arg => undef, default => sub { {} } );
has 'request_path'       => ( init_arg => undef );
has 'run_params'         => ( init_arg => undef );

# Class attributes
#
our $current_request;
method current_request () { $current_request }

#
# BUILD
#

method BUILD ($params) {
    $self->_push_buffer();
    $self->{orig_request_params} = $params;
    $self->{count}               = $self->{interp}->_incr_request_count;
}

#
# PUBLIC METHODS
#

method abort ($aborted_value) {
    Mason::Exception::Abort->throw(
        error         => 'Request->abort was called',
        aborted_value => $aborted_value
    );
}

method aborted ($err) {
    return blessed($err) && $err->isa('Mason::Exception::Abort');
}

method apply_filter ($filter, $yield) {
    my $filtered_output;
    $yield = sub { $yield }
      if !ref($yield);
    if ( ref($filter) eq 'CODE' ) {
        $filtered_output = $filter->( $yield->() );
    }
    elsif ( blessed($filter) && $filter->can('apply_filter') ) {
        $filtered_output = $filter->apply_filter($yield);
    }
    else {
        die "'$filter' is neither a code ref nor a filter object";
    }
    return $filtered_output;
}

method capture ($code) {
    my $output;
    {
        $self->_push_buffer;
        scope_guard { $output = ${ $self->_current_buffer }; $self->_pop_buffer };
        $code->();
    }
    return $output;
}

method clear_and_abort () {
    $self->clear_buffer;
    $self->abort(@_);
}

method clear_buffer () {
    foreach my $buffer ( @{ $self->buffer_stack } ) {
        $$buffer = '';
    }
}

method comp () {
    $self->construct(@_)->main();
}

method comp_exists ($path) {
    return $self->interp->comp_exists( $self->rel_to_abs($path) );
}

method construct () {
    my $path  = shift;
    my $compc = $self->load($path)
      or $self->_comp_not_found($path);
    return $compc->new( @_, 'm' => $self );
}

method create_result_object () {
    return $self->interp->result_class->new(@_);
}

method flush_buffer () {
    my $request_buffer = $self->_request_buffer;
    $self->out_method->( $$request_buffer, $self )
      if length $$request_buffer;
    $$request_buffer = '';
}

method go () {
    my @extra_request_params;
    while ( ref( $_[0] ) eq 'HASH' ) {
        push( @extra_request_params, shift(@_) );
    }
    my $path = $self->rel_to_abs( shift(@_) );
    $self->clear_buffer;
    my $result =
      $self->interp->run( $self->{orig_request_params}, @extra_request_params, $path, @_ );
    $self->{go_result} = $result;
    $self->abort();
}

method load ($path) {
    my $compc = $self->interp->load( $self->rel_to_abs($path) );
}

method log () {
    return $self->_current_comp_class->cmeta->log();
}

method notes () {
    return $self->{notes}
      unless @_;
    my $key = shift;
    return $self->{notes}->{$key} unless @_;
    return $self->{notes}->{$key} = shift;
}

method print () {
    my $buffer = $self->_current_buffer;
    for (@_) {
        $$buffer .= $_ if defined;
    }
}

method rel_to_abs ($path) {
    $path = join( "/", $self->_current_comp_class->cmeta->dir_path, $path )
      unless substr( $path, 0, 1 ) eq '/';
    return $path;
}

method scomp () {
    my $buf = $self->capture( sub { $self->comp(@_) } );
    return $buf;
}

method visit () {
    my @extra_request_params;
    while ( ref( $_[0] ) eq 'HASH' ) {
        push( @extra_request_params, shift(@_) );
    }
    my $path = $self->rel_to_abs( shift(@_) );
    my $retval = $self->interp->run( { out_method => \my $buf }, @extra_request_params, $path, @_ );
    $self->print($buf);
    return $retval;
}

#
# MODIFIABLE METHODS
#

method cleanup_request () {
    $self->interp->_flush_load_cache();
}

method construct_page_component ($compc, $args) {
    return $compc->new( %$args, 'm' => $self );
}

method dispatch_to_page_component ($page) {
    $self->catch_abort( sub { $page->render() } );
}

method catch_abort ($code) {
    my $retval;
    try {
        $retval = $code->();
    }
    catch {
        my $err = $_;
        if ( $self->aborted($err) ) {
            $retval = $err->aborted_value;
        }
        else {
            die $err;
        }
    };
    return $retval;
}

method resolve_page_component ($request_path) {
    my $compc = $self->interp->load($request_path);
    return ( defined($compc) && $compc->cmeta->is_top_level ) ? $compc : undef;
}

method run () {

    # Get path and either hash or hashref of arguments
    #
    my $path = shift;
    my $args;
    if ( @_ == 1 && reftype( $_[0] ) eq 'HASH' ) {
        $args = shift;
    }
    else {
        $args = {@_};
    }

    # Flush interp load cache
    #
    $self->interp->_flush_load_cache();

    # Make this the current request until end of scope. Use a guard
    # because 'local' doesn't work with the $m alias inside components.
    #
    my $save_current_request = $current_request;
    scope_guard { $current_request = $save_current_request };
    $current_request = $self;

    # Save off the requested path and args
    #
    $self->{request_path} = $path;
    $self->{request_args} = $args;

    # Check the static_source touch file, if it exists, before the
    # first component is loaded.
    #
    $self->interp->_check_static_source_touch_file();

    # Clean up after request
    #
    scope_guard { $self->cleanup_request() };

    # Resolve the path to a page component and render it
    #
    my $retval = $self->resolve_and_render_path( $path, $args );

    # If go() was called in this request, return the result of the subrequest
    #
    return $self->go_result if defined( $self->go_result );

    # Send output to its final destination
    #
    $self->flush_buffer;

    # Create and return result object
    #
    return $self->create_result_object( output => $self->output, retval => $retval );
}

method resolve_and_render_path ($path, $args) {

    # Find request component class.
    #
    my $compc = $self->resolve_page_component($path);
    if ( !defined($compc) ) {
        Mason::Exception::TopLevelNotFound->throw(
            error => sprintf(
                "could not find top-level component for path '%s' - component root is [%s]",
                $path, join( ", ", @{ $self->interp->comp_root } )
            )
        );
    }

    # Construct page component.
    #
    my $page = $self->construct_page_component( $compc, $args );
    $self->{page} = $page;
    $log->debugf( "starting request with component '%s'", $page->cmeta->path )
      if $log->is_debug;

    # Dispatch to page component, with 'print' tied to component output.
    # Will catch aborts but throw other fatal errors.
    #
    my $retval = $self->with_tied_print( sub { $self->dispatch_to_page_component($page) } );
}

method with_tied_print ($code) {
    local *TH;
    tie *TH, 'Mason::TieHandle';
    my $old = select TH;
    scope_guard { select $old };
    return $code->();
}

#
# PRIVATE METHODS
#

method _apply_filters ($filters, $yield) {
    if ( !@$filters ) {
        return $yield->();
    }
    else {
        my @filters = @$filters;
        my $filter  = pop(@filters);
        return $self->_apply_filters( \@filters, sub { $self->apply_filter( $filter, $yield ) } );
    }
}

method _apply_filters_to_output ($filters, $output_method) {
    my $yield = sub {
        $self->capture( sub { $output_method->() } );
    };
    my $filtered_output = $self->_apply_filters( $filters, $yield );
    $self->print($filtered_output);
}

method _comp_not_found ($path) {
    croak sprintf( "could not find component for path '%s' - component root is [%s]",
        $path, join( ", ", @{ $self->interp->comp_root } ) );
}

method _current_buffer () {
    $self->{buffer_stack}->[-1];
}

method _current_comp_class () {
    my $cnt = 1;
    while (1) {
        if ( my $pkg = ( caller($cnt) )[0] ) {
            return $pkg if $pkg->isa('Mason::Component') && $pkg ne 'Mason::Component';
        }
        else {
            confess("cannot determine current_comp_class from stack");
        }
        $cnt++;
    }
}

method _pop_buffer () {
    pop( @{ $self->{buffer_stack} } );
}

method _push_buffer () {
    my $s = '';
    push( @{ $self->{buffer_stack} }, \$s );
}

method _request_buffer () {
    $self->{buffer_stack}->[0];
}

__PACKAGE__->meta->make_immutable();

1;

# ABSTRACT: Mason Request Class
__END__

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

The methods L<comp>, L<comp_exists>, L<construct>, L<go>, L<load>, and L<visit>
take a component path argument. If the path does not begin with a '/', then it
is made absolute based on the current component path (using L<rel_to_abs>).

Component paths are like URL paths, and always use a forward slash (/) as the
separator, regardless of what your operating system uses.

=head1 PARAMETERS TO THE new() CONSTRUCTOR

=over

=item out_method

Indicates where to send the page output. If out_method is a scalar reference,
output is appended to the scalar.  If out_method is a code reference, the code
is called with the output string. For example, to send output to a file called
"mason.out":

    open(my $fh, ">", "mason.out);
    ...
    out_method => sub { $fh->print($_[0]) }

When C<out_method> is unspecified, the output can be obtained from the
L<Mason::Result|Mason::Result> object returned from C<< $interp->run >>.

=back

=head1 PUBLIC METHODS

=over

=item abort ([return value])

Ends the current request, finishing the page without returning through
components. The optional argument specifies the return value to be placed in
L<Mason::Result/retval>.

C<abort> is implemented by throwing an C<Mason::Exception::Abort> object and
can thus be caught by C<eval>. The C<aborted> method is a shortcut for
determining whether a caught error was generated by C<abort>.

=item aborted ([$err])

Returns true or undef indicating whether the specified C<$err> was generated by
C<abort>. If no C<$err> was passed, uses C<$@>.

In this L<Try::Tiny|Try::Tiny> code, we catch and process fatal errors while
letting C<abort> exceptions pass through:

    try {
        code_that_may_fail_or_abort()
    } catch {
        die $_ if $m->aborted($_);
        # handle fatal errors...
    };

=item clear_and_abort ([return value])

This method is syntactic sugar for calling C<clear_buffer()> and then
C<abort()>.  If you are aborting the request because of an error (or, in a web
environment, to do a redirect), you will often want to clear the buffer first
so that any output generated up to that point is not sent to the client.

=item capture (code)

Execute the I<code>, capturing and returning any Mason output instead of
outputting it. e.g. the following

    my $buf = $m->capture(sub { $m->comp('/foo') });

is equivalent to

    my $buf = $m->scomp('/foo');

=item clear_buffer ()

Clears the Mason output buffer. Any output sent before this line is discarded.
Useful for handling error conditions that can only be detected in the middle of
a request.

clear_buffer is, of course, thwarted by L</flush_buffer>.

=item comp (path[, params ...])

Creates a new instance of the component designated by I<path>, and calls its
C<main> method. I<params>, if any, are passed to the constructor.

The C<< <& &> >> tag provides a shortcut for C<$m-E<gt>comp>.

=item comp_exists (path)

Makes the component I<path> absolute if necessary, and calls L<Interp
comp_exists|Mason::Interp/comp_exists> to determine whether a component exists
at that path.

=item count ()

Returns the number of this request for the interpreter, a monotonically
increasing integer starting at 0.

=item current_comp_class ()

Returns the current component class. This is determined by walking up the Perl
caller() stack until the first Mason::Component subclass is found.

=item current_request ()

This class method returns the C<Mason::Request> currently in use.  If called
when no Mason request is active it will return C<undef>.

=item construct (path[, params ...])

Constructs and return a new instance of the component designated by I<path>.
I<params>, if any, are passed to the constructor. Throws an error if I<path>
does not exist.

=item flush_buffer ()

Flushes the main output buffer. Anything currently in the buffer is sent to the
request's L</out_method>.

Note that anything output within a C<< $m->scomp >> or C<< $m->capture >> will
not have made it to the main output buffer, and thus cannot be flushed.

=item go ([request params], path, args...)

Performs an internal redirect. Clears the output buffer, runs a new request for
the given I<path> and I<args>, and then L<aborts|/abort> when that request is
done.

The first argument may optionally be a hashref of parameters which are passed
to the C<Mason::Request> constructor.

See also L</visit>.

=item interp ()

Returns the L<Interp|Mason::Interp> object associated with this request.

=item load (path)

Makes the component I<path> absolute if necessary, and calls L<Interp
load|Mason::Interp/load> to load the component class associated with the path.

=item log ()

Returns a C<Log::Any> logger with a log category specific to the current
component.  The category for a component "/foo/bar" would be
"Mason::Component::foo::bar".

=item notes ([key[, value]])

The C<notes()> method provides a place to store application data between
components - essentially, a hash which persists for the duration of the
request.

C<notes($key, $value)> stores a new entry in the hash; C<notes($key)> returns a
previously stored value; and C<notes()> without any arguments returns a
reference to the entire hash of key-value pairs.

Consider storing this kind of data in a read-write attribute of the page
component.

=item print (string)

Add the given I<string> to the Mason output buffer. This happens implicitly for
all content placed in the main component body.

=item page ()

Returns the page component originally called in the request.

=item rel_to_abs (path)

Converts a component I<path> to absolute form based on the current component,
if it does not already begin with a '/'.

=item request_args ()

Returns the original hashref of arguments passed to the request, e.g. via C<<
$interp->run >>.

=item request_path ()

Returns the original path passed to the request, e.g. in C<< $interp->run >>.

=item scomp (comp, args...)

Like L<comp|Mason::Request/item_comp>, but returns the component output as a
string instead of printing it. (Think sprintf versus printf.)

=item visit ([request params], path, args...)

Performs a subrequest with the given I<path> and I<args>, with output being
sent to the current output buffer.

The first argument may optionally be a hashref of parameters which are passed
to the C<Mason::Request> constructor. e.g. to capture the output of the
subrequest:

    $m->visit({out_method => \my $buffer}, ...);

See also L</go>.

=back

=head1 MODIFIABLE METHODS

These methods are not intended to be called externally, but may be useful to
modify with method modifiers in plugins and subclasses. Their APIs will be kept
as stable as possible.

=over

=item cleanup_request ()

A place to perform cleanup duties when the request finishes or dies with an
error, even if the request object is not immediately destroyed.

=item construct_page_component ($compc, $args)

Constructs the page component of class I<$compc>, with hashref of constructor
arguments I<$args>.

=item dispatch_to_page_component ($page)

Call dispatch on component object I<$page> within a try/catch block. C<< abort
>> calls are caught while other errors are repropagated.

=item resolve_page_component ($request_path)

Given a top level I<$request_path>, return a corresponding component class or
undef if none was found. By default this simply tries to load the path, but the
L<AdvancedPageResolution|Mason::Plugin::AdvancedPageResolution> plugin adds
much to this.

=item run (request_path, args)

Runs the request with I<request_path> and I<args>, where the latter can be
either a hashref or a hash. This is generally called via << $interp->run >>.

=item with_tied_print ($code)

Execute the given I<$code> with the current selected filehandle ('print') tied
to the Mason output stream. You could disable the filehandle selection by
overriding this to just call I<$code>.

=back

=cut
