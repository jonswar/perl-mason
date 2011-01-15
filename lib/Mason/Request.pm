package Mason::Request;
use autodie qw(:all);
use Carp;
use File::Basename;
use Guard;
use Log::Any qw($log);
use Mason::Exceptions;
use Mason::TieHandle;
use Mason::Types;
use Moose;
use Mason::Moose;
use Scalar::Util qw(blessed);
use Try::Tiny;
use strict;
use warnings;

my $default_out = sub { my ( $text, $self ) = @_; $self->{output} .= $text };

# Passed attributes
#
has 'declined_paths' => ( default => sub { {} } );
has 'interp'         => ( required => 1, weak_ref => 1 );
has 'out_method'     => ( isa => 'Mason::Types::OutMethod', default => sub { $default_out }, coerce => 1 );
has 'request_params'     => ( required => 1 );

# Derived attributes
#
has 'buffer_stack'       => ( init_arg => undef );
has 'count'              => ( init_arg => undef );
has 'go_result'          => ( init_arg => undef );
has 'path_info'          => ( init_arg => undef, default => '' );
has 'output'             => ( init_arg => undef, default => '' );
has 'page'               => ( init_arg => undef );
has 'request_args'       => ( init_arg => undef );
has 'request_code_cache' => ( init_arg => undef );
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
    $self->{request_code_cache} = {};
    $self->{count}              = $self->{interp}->request_count;
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

method call_next () {
    return $self->_current_comp_class->_inner();
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
    $self->_construct_or_die(@_)->main();
}

method comp_exists ($path) {
    return $self->interp->comp_exists( $self->rel_to_abs($path) );
}

method decline () {
    $self->go( { declined_paths => { %{ $self->declined_paths }, $self->page->cmeta->path => 1 } },
        $self->request_path, @{ $self->request_args } );
}

method construct () {
    my $path  = shift;
    my $compc = $self->load($path);
    return undef unless defined($compc);

    # Create and return a component instance
    #
    my $comp = $compc->new( @_, 'm' => $self );

    return $comp;
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
    my $result = $self->interp->run( $self->request_params, @extra_request_params, $path, @_ );
    $self->{go_result} = $result;
    $self->abort();
}

method load ($path) {
    return $self->interp->load( $self->rel_to_abs($path) );
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

method resolve_request_path_to_component ($request_path) {
    my $compc = $self->interp->load($request_path);
    return ( defined($compc) && $compc->cmeta->is_external ) ? $compc : undef;
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

    # Save off the requested path and args, e.g. for decline.
    #
    $self->{request_path} = $path;
    $self->{request_args} = [@_];

    # Check the static_source touch file, if it exists, before the
    # first component is loaded.
    #
    $self->interp->check_static_source_touch_file();

    # Find request component class.
    #
    my $compc = $self->resolve_request_path_to_component($path);
    if ( !defined($compc) ) {
        croak sprintf( "could not find top-level component for path '%s' - component root is [%s]",
            $path, join( ", ", @{ $self->interp->comp_root } ) );
    }

    $self->_comp_not_found($path) if !defined($compc);

    my $page = $compc->new( @_, 'm' => $self );
    $self->{page} = $page;
    $log->debugf( "starting request with component '%s'", $page->cmeta->path )
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
            $retval = $page->dispatch();
        }
        catch {
            $err = $_;
            die $err if !$self->aborted($err);
        };
    }

    # If go() was called in this request, return the result of the subrequest
    #
    return $self->{go_result} if defined( $self->{go_result} );

    # Send output to its final destination
    #
    $self->flush_buffer;

    # Create and return result object
    #
    $retval = $self->aborted($err) ? $err->aborted_value : $retval;
    return $self->_create_result_object( output => $self->output, retval => $retval );
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

method _create_result_object () {
    return $self->interp->result_class->new(@_);
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

method _construct_or_die () {
    my $comp = $self->construct(@_)
      or $self->_comp_not_found( $_[0] );
    return $comp;
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

=head1 METHODS

=over

=item abort ([return value])

Ends the current request, finishing the page without returning through
components. The optional argument specifies the return value from
C<Interp::run>; in a web environment, this ultimately becomes the HTTP status
code.

C<abort> is implemented by throwing an Mason::Exception::Abort object and can
thus be caught by eval(). The C<aborted> method is a shortcut for determining
whether a caught error was generated by C<abort>.

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
C<abort()>.  If you are aborting the request because of an error, you will
often want to clear the buffer first so that any output generated up to that
point is not sent to the client.

=item capture (code)

Execute the I<code>, capturing and returning any Mason output instead of
outputting it. e.g. the following

    my $buf = $m->capture(sub { $m->comp('/foo') });

is equivalent to

    my $buf = $m->scomp('/foo');

=item clear_buffer

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

=item count

Returns the number of this request, which is unique for a given request and
interpreter.

=item current_comp_class

Returns the current component class.

=item current_request

This class method returns the C<Mason::Request> currently in use.  If called
when no Mason request is active it will return C<undef>.

=item construct (path[, params ...])

Constructs and return a new instance of the component designated by I<path>.
I<params>, if any, are passed to the constructor.

=item flush_buffer

Flushes the Mason output buffer. Anything currently in the buffer is sent to
the request's L</out_method>.

Attempts to flush the buffers are ignored within the context of a call to C<<
$m->scomp >> or C<< $m->capture >>, or within a filter.

=item go ([request params], path, args...)

Performs an internal redirect. Clears the output buffer, runs a new request for
the given I<path> and I<args>, and then L<aborts|/abort> when that request is
done.

The first argument may optionally be a hashref of parameters which are passed
to the C<Mason::Request> constructor.

See also L</visit>.

=item interp

Returns the L<Interp|Mason::Interp> object associated with this request.

=item load (path)

Makes the component I<path> absolute if necessary, and calls L<Interp
load|Mason::Interp/load> to load the component class associated with the path.

=item log

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

=item path_info

Returns the remainder of the top level path beyond the path of the page
component, with no leading slash. e.g. If a request for '/foo/bar/baz' resolves
to "/foo.m", the path_info is "bar/baz". Defaults to the empty string for an
exact match.

=item print (string)

Add the given I<string> to the Mason output buffer. This happens implicitly for
all content placed in the main component body.

=item page

Returns the page component originally called in the request.

=item rel_to_abs (path)

Converts a component I<path> to absolute form based on the current component,
if it does not already begin with a '/'.

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

=cut
