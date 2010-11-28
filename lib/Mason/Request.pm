package Mason::Request;
use autodie qw(:all);
use Carp;
use Guard;
use Log::Any qw($log);
use Mason::TieHandle;
use Mason::Types;
use Method::Signatures::Simple;
use Moose;
use Scalar::Util qw(blessed);
use strict;
use warnings;

my $default_out = sub { print $_[0] };

# Passed attributes
has 'interp' => ( is => 'ro', required => 1, weak_ref => 1 );
has 'out_method' =>
  ( is => 'ro', isa => 'Mason::Types::OutMethod', default => sub { $default_out }, coerce => 1 );

# Derived attributes
has 'buffer_stack'       => ( is => 'ro', init_arg => undef );
has 'current_comp'       => ( is => 'ro', init_arg => undef );
has 'request_comp'       => ( is => 'ro', init_arg => undef );
has 'request_code_cache' => ( is => 'ro', init_arg => undef );

# Class attributes
our $current_request;
method current_request() { $current_request }

method BUILD($params) {
    $self->push_buffer();
    $self->{request_code_cache} = {};
}

method run() {
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

    # Fetch request component.
    #
    my $request_comp = $self->fetch_comp_or_die( $path, @_ );
    $self->{request_comp} = $request_comp;
    $log->debugf( "starting request for '%s'", $request_comp->title )
      if $log->is_debug;

    my ( $retval, $err );
    {
        local *TH;
        tie *TH, 'Mason::TieHandle';
        my $old = select TH;
        scope_guard { select $old };

        $retval = eval { $request_comp->render() };
        $err = $@;
    }
    die $err if $err && !$self->_aborted_or_declined;

    # Send output to its final destination
    #
    $self->flush_buffer;

    # Flush interp load cache
    #
    $self->interp->flush_load_cache();

    # Return aborted value or result.
    #
    return $self->aborted($err) ? $err->aborted_value : $retval;
}

method clear_and_abort() {
    $self->clear_buffer;
    $self->abort(@_);
}

method abort($aborted_value) {
    Mason::Exception::Abort->throw(
        error         => 'Request->abort was called',
        aborted_value => $aborted_value
    );
}

#
# Determine whether $err (or $@ by default) is an Abort exception.
#
method aborted($err) {
    $err = $@
      if !defined($err);
    return blessed($err) && $err->isa('Mason::Exception::Abort');
}

#
# Determine whether $err (or $@ by default) is a Decline exception.
#
method declined($err) {
    $err = $@
      if !defined($err);
    return blessed($err) && $err->isa('Mason::Exception::Decline');
}

method _aborted_or_declined($err) {
    return $self->aborted($err) || $self->declined($err);
}

# Return a CHI cache object specific to this component.
#
method cache(%options) {
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

method comp_exists($path) {
    return $self->load($path) ? 1 : 0;
}

method decline() {

    # TODO
}

method fetch_comp() {

    my $path = shift;
    return undef unless defined($path);

    # Make absolute based on current component path
    #
    $path = join( "/", $self->current_comp->comp_dir_path, $path )
      unless substr( $path, 0, 1 ) eq '/';

    # Load the component class
    #
    my $compc = $self->interp->load($path)
      or return undef;

    # Create and return a component instance
    #
    my $comp = $compc->new( @_, comp_request => $self );

    return $comp;
}

method fetch_comp_or_die() {
    my $comp = $self->fetch_comp(@_)
      or croak sprintf( "could not find component for path '%s' - component root is [%s]",
        $_[0], join( ", ", @{ $self->interp->comp_root } ) );
    return $comp;
}

method print() {
    my $buffer = $self->current_buffer;
    for (@_) {
        $$buffer .= $_ if defined;
    }
}

# Execute the given component
#
method comp() {
    $self->fetch_comp_or_die(@_)->main();
}

# Like comp, but return component output.
#
method scomp() {
    $self->capture( \my $buf, sub { $self->comp(@_) } );
    return $buf;
}

method notes() {
    return $self->{notes}
      unless @_;
    my $key = shift;
    return $self->{notes}->{$key} unless @_;
    return $self->{notes}->{$key} = shift;
}

method clear_buffer() {
    foreach my $buffer ( $self->buffer_stack ) {
        $$buffer = '';
    }
}

method flush_buffer() {
    my $request_buffer = $self->request_buffer;
    $self->out_method->($$request_buffer)
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

method log() {
    return $self->current_comp->comp_logger();
}

# Buffer stack
#
method push_buffer() { my $s = ''; push( @{ $self->{buffer_stack} }, \$s ); }
method pop_buffer()     { pop( @{ $self->{buffer_stack} } ) }
method request_buffer() { $self->{buffer_stack}->[0]; }
method current_buffer() { $self->{buffer_stack}->[-1] }

method capture( $output_ref, $code ) {
    $self->push_buffer;
    scope_guard { $$output_ref = ${ $self->current_buffer }; $self->pop_buffer };
    $code->();
}

method apply_immediate_filter( $filter_code, $code ) {
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

The Request API is your gateway to all Mason features not provided by syntactic
tags. Mason creates a new Request object for every page request. Inside a
component you access the current request object via the global C<$m>.  Outside
of a component, you can use the class method C<Mason::Request->instance>.

=head1 COMPONENT PATHS

The methods L<Request-E<gt>comp|Mason::Request/item_comp>,
L<Request-E<gt>comp_exists|Mason::Request/item_comp_exists>, and
L<Request-E<gt>fetch_comp|Mason::Request/item_fetch_comp> take a component path
argument.  Component paths are like URL paths, and always use a forward slash
(/) as the separator, regardless of what your operating system uses.

=over

=item *

If the path is absolute (starting with a '/'), then the component is found
relative to the component root.

=item *

If the path is relative (no leading '/'), then the component is found relative
to the current component directory.

=item *

If the path matches both a subcomponent and file-based component, the
subcomponent takes precedence.

=back

=head1 PARAMETERS TO THE new() CONSTRUCTOR

=over

=item out_method

Indicates where to send the final page output. If out_method is a reference to
a scalar, output is appended to the scalar.  If out_method is a reference to a
subroutine, the subroutine is called with each output string. For example, to
send output to a file called "mason.out":

    my $fh = new IO::File ">mason.out";
    ...
    out_method => sub { $fh->print($_[0]) }

By default, out_method prints to standard output.

=back

=head1 OTHER METHODS

=over

=item abort ([return value])

=for html <a name="item_abort"></a>

Ends the current request, finishing the page without returning through
components. The optional argument specifies the return value from
C<Interp::exec>; in a web environment, this ultimately becomes the HTTP status
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

In this code, we catch and process fatal errors while letting C<abort>
exceptions pass through:

    eval { code_that_may_fail_or_abort() };
    if ($@) {
        die $@ if $m->aborted;

        # handle fatal errors...

C<$@> can lose its value quickly, so if you are planning to call $m->aborted
more than a few lines after the eval, you should save $@ to a temporary
variable.

=item base_comp

=for html <a name="item_base_comp"></a>

Returns the current base component.

Here are the rules that determine base_comp as you move from component to
component.

=over

=item * At the beginning of a request, the base component is
initialized to the requested component (C<< $m->request_comp() >>).

=item * When you call a regular component via a path, the base
component changes to the called component.

=item * When you call a component method via a path (/foo/bar:baz),
the base component changes to the method's owner.

=item * The base component does not change when:

=over

=item * a component call is made to a component object

=item * a component call is made to SELF:x or PARENT:x or REQUEST:x

=item * a component call is made to a subcomponent (<%def>)

=back

=back

This may return nothing if the base component is not yet known, for example
inside a plugin's C<start_request_hook()> method, where we have created a
request but it does not yet know anything about the component being called.

=item cache

=for html <a name="item_cache"></a>

C<$m-E<gt>cache> returns a new L<cache object|Mason::Cache::BaseCache> with a
namespace specific to this component. The parameters to and return value from
C<$m-E<gt>cache> differ depending on which L<data_cache_api> you are using.

=over

=item If data_cache_api = 1.1 (default)

I<cache_class> specifies the class of cache object to create. It defaults to
C<FileCache> in most cases, or C<MemoryCache> if the interpreter has no data
directory, and must be a backend subclass of C<Cache::Cache>. The prefix
"Cache::" need not be included.  See the C<Cache::Cache> package for a full
list of backend subclasses.

Beyond that, I<cache_options> may include any valid options to the new() method
of the cache class. e.g. for C<FileCache>, valid options include
C<default_expires_in> and C<cache_depth>.

See L<Mason::Cache::BaseCache|Mason::Cache::BaseCache> for information about
the object returend from C<$m-E<gt>cache>.

=item If data_cache_api = CHI

I<chi_root_class> specifies the factory class that will be called to create
cache objects. The default is 'CHI'.

I<driver> specifies the driver to use, for example C<Memory> or C<FastMmap>. 
The default is C<File> in most cases, or C<Memory> if the interpreter has no
data directory.

Beyond that, I<cache_options> may include any valid options to the new() method
of the driver. e.g. for the C<File> driver, valid options include C<expires_in>
and C<depth>.

=back

=item cache_self ([expires_in => '...'], [key => '...'], [get_options], [cache_options])

=for html <a name="item_cache_self"></a>

C<$m-E<gt>cache_self> caches the entire output and return result of a
component.

C<cache_self> either returns undef, or a list containing the return value of
the component followed by '1'. You should return immediately upon getting the
latter result, as this indicates that you are inside the second invocation of
the component.

C<cache_self> takes any of parameters to C<$m-E<gt>cache> (e.g.
I<cache_depth>), any of the optional parameters to C<$cache-E<gt>get>
(I<expire_if>, I<busy_lock>), and two additional options:

=over

=item *

I<expire_in> or I<expires_in>: Indicates when the cache expires - it is passed
as the third argument to C<$cache-E<gt>set>. e.g. '10 sec', '5 min', '2 hours'.

=item *

I<key>: An identifier used to uniquely identify the cache results - it is
passed as the first argument to C<$cache-E<gt>get> and C<$cache-E<gt>set>.  The
default key is '__mason_cache_self__'.

=back

To cache the component's output:

    <%init>
    return if $m->cache_self(expire_in => '10 sec'[, key => 'fookey']);
    ... <rest of init> ...
    </%init>

To cache the component's scalar return value:

    <%init>
    my ($result, $cached) = $m->cache_self(expire_in => '5 min'[, key => 'fookey']);

    return $result if $cached;
    ... <rest of init> ...
    </%init>

To cache the component's list return value:

    <%init>
    my (@retval) = $m->cache_self(expire_in => '3 hours'[, key => 'fookey']);

    return @retval if pop @retval;
    ... <rest of init> ...
    </%init>

We call C<pop> on C<@retval> to remove the mandatory '1' at the end of the
list.

If a component has a C<< <%filter> >> block, then the I<filtered> output is
cached.

Note: users upgrading from 1.0x and earlier can continue to use the old
C<$m-E<gt>cache_self> API by setting data_cache_api to '1.0'. This support will
be removed at a later date.

See the DEVEL<DATA CACHING> section for more details on how to exercise finer
control over caching.

=item caller_args

=for html <a name="item_caller_args"></a>

Returns the arguments passed by the component at the specified stack level. Use
a positive argument to count from the current component and a negative argument
to count from the component at the bottom of the stack. e.g.

    $m->caller_args(0)   # arguments passed to current component
    $m->caller_args(1)   # arguments passed to component that called us
    $m->caller_args(-1)  # arguments passed to first component executed

When called in scalar context, a hash reference is returned.  When called in
list context, a list of arguments (which may be assigned to a hash) is
returned.  Returns undef or an empty list, depending on context, if the
specified stack level does not exist.

=item callers

=for html <a name="item_callers"></a>

With no arguments, returns the current component stack as a list of component
objects, starting with the current component and ending with the top-level
component. With one numeric argument, returns the component object at that
index in the list. Use a positive argument to count from the current component
and a negative argument to count from the component at the bottom of the stack.
e.g.

    my @comps = $m->callers   # all components
    $m->callers(0)            # current component
    $m->callers(1)            # component that called us
    $m->callers(-1)           # first component executed

Returns undef or an empty list, depending on context, if the specified stack
level does not exist.

=item caller

=for html <a name="item_caller"></a>

A synonym for C<< $m->callers(1) >>, i.e. the component that called the
currently executing component.

=item call_next ([args...])

=for html <a name="item_call_next"></a>

Calls the next component in the content wrapping chain; usually called from an
autohandler. With no arguments, the original arguments are passed to the
component.  Any arguments specified here serve to augment and override (in case
of conflict) the original arguments. Works like C<$m-E<gt>comp> in terms of
return value and scalar/list context.  See DEVEL<autohandlers> for examples.

=item call_self (output, return, error, tag)

This method allows a component to call itself so that it can filter both its
output and return values.  It is fairly advanced; for most purposes the C<<
<%filter> >> tag will be sufficient and simpler.

C<< $m->call_self >> takes four arguments, all of them optional.

=over

=item output - scalar reference that will be populated with the
component output.

=item return - scalar reference that will be populated with the
component return value.

=item error - scalar reference that will be populated with the error
thrown by the component, if any. If this parameter is not defined,
then call_self will not catch errors.

=item tag - a name for this call_self invocation; can almost always be omitted.

=back

C<< $m->call_self >> acts like a C<fork()> in the sense that it will return
twice with different values.  When it returns 0, you allow control to pass
through to the rest of your component.  When it returns 1, that means the
component has finished and you can examine the output, return value and error.
(Don't worry, it doesn't really do a fork! See next section for explanation.)

The following examples would generally appear at the top of a C<< <%init> >>
section.  Here is a no-op C<< $m->call_self >> that leaves the output and
return value untouched:

    <%init>
    my ($output, $retval);
    if ($m->call_self(\$output, \$retval)) {
        $m->print($output);
        return $retval;
    }
    ...

Here is a simple output filter that makes the output all uppercase. Note that
we ignore both the original and the final return value.

    <%init>
    my ($output, $error);
    if ($m->call_self(\$output, undef)) {
        $m->print(uc $output);
        return;
    }
    ...

Here is a piece of code that traps all errors occuring anywhere in a component
or its children, e.g. for the purpose of handling application-specific
exceptions. This is difficult to do with a manual C<eval> because it would have
to span multiple code sections and the main component body.

    <%init>
    my ($output, undef, $error);
    if ($m->call_self(\$output, undef, \$error)) {
        if ($error) {
            # check $error and do something with it
        }
        $m->print($output);
        return;
    }
    ...

=item clear_buffer

=for html <a name="item_clear_buffer"></a>

Clears the Mason output buffer. Any output sent before this line is discarded.
Useful for handling error conditions that can only be detected in the middle of
a request.

clear_buffer is, of course, thwarted by C<flush_buffer>.

=item comp (comp, args...)

=for html <a name="item_comp"></a>

Calls the component designated by I<comp> with the specified option/value
pairs. I<comp> may be a component path or a component object.

Components work exactly like Perl subroutines in terms of return values and
context. A component can return any type of value, which is then returned from
the C<$m-E<gt>comp> call.

The <& &> tag provides a convenient shortcut for C<$m-E<gt>comp>.

As of 1.10, component calls can accept an initial hash reference of
I<modifiers>.  The only currently supported modifier is C<store>, which stores
the component's output in a scalar reference. For example:

  my $buf;
  my $return = $m->comp( { store => \$buf }, '/some/comp', type => 'big' );

This mostly duplicates the behavior of I<scomp>, but can be useful in rare
cases where you need to capture both a component's output and return value.

This modifier can be used with the <& &> tag as well, for example:

  <& { store => \$buf }, '/some/comp', size => 'medium' &>

=item comp_exists (comp_path)

=for html <a name="item_comp_exists"></a>

Returns 1 if I<comp_path> is the path of an existing component, 0 otherwise. 
I<comp_path> may be any path accepted by L<comp|Mason::Request/item_comp> or
L<fetch_comp|Mason::Request/item_fetch_comp>, including method or subcomponent
paths.

Depending on implementation, <comp_exists> may try to load the component
referred to by the path, and may throw an error if the component contains a
syntax error.

=item content

=for html <a name="content"></a>

Evaluates the content (passed between <&| comp &> and </&> tags) of the 
current component, and returns the resulting text.

Returns undef if there is no content.

=item has_content

=for html <a name="has_content"></a>

Returns true if the component was called with content (i.e. with <&| comp &>
and </&> tags instead of a single <& comp &> tag). This is generally better
than checking the defined'ness of C<< $m->content >> because it will not try to
evaluate the content.

=item count

=for html <a name="item_count"></a>

Returns the number of this request, which is unique for a given request and
interpreter.

=item current_args

=for html <a name="item_current_args"></a>

Returns the arguments passed to the current component. When called in scalar
context, a hash reference is returned.  When called in list context, a list of
arguments (which may be assigned to a hash) is returned.

=item current_comp

=for html <a name="item_current_comp"></a>

Returns the current component object.

=item decline

=for html <a name="item_decline"></a>

Used from a top-level component or dhandler, this method clears the output
buffer, aborts the current request and restarts with the next applicable
dhandler up the tree. If no dhandler is available, a not-found error occurs.

This method bears no relation to the Apache DECLINED status except in name.

=item declined ([$err])

=for html <a name="item_declined"></a>

Returns true or undef indicating whether the specified C<$err> was generated by
C<decline>. If no C<$err> was passed, uses C<$@>.

=item depth

=for html <a name="item_depth"></a>

Returns the current size of the component stack.  The lowest possible value is
1, which indicates we are in the top-level component.

=item dhandler_arg

=for html <a name="item_dhandler_arg"></a>

If the request has been handled by a dhandler, this method returns the
remainder of the URI or C<Interp::exec> path when the dhandler directory is
removed. Otherwise returns undef.

C<dhandler_arg> may be called from any component in the request, not just the
dhandler.

=item exec (comp, args...)

=for html <a name="item_exec"></a>

Starts the request by executing the top-level component and arguments. This is
normally called for you on the main request, but you can use it to execute
subrequests.

A request can only be executed once; e.g. it is an error to call this
recursively on the same request.

=item fetch_comp (comp_path)

=for html <a name="item_fetch_comp"></a>

Given a I<comp_path>, returns the corresponding component object or undef if no
such component exists.

=item fetch_next

=for html <a name="item_fetch_next"></a>

Returns the next component in the content wrapping chain, or undef if there is
no next component. Usually called from an autohandler.  See DEVEL<autohandlers>
for usage and examples.

=item fetch_next_all

=for html <a name="item_fetch_next_all"></a>

Returns a list of the remaining components in the content wrapping chain.
Usually called from an autohandler.  See DEVEL<autohandlers> for usage and
examples.

=item file (filename)

=for html <a name="item_file"></a>

Returns the contents of I<filename> as a string. If I<filename> is a relative
path, Mason prepends the current component directory.

=item flush_buffer

=for html <a name="item_flush_buffer"></a>

Flushes the Mason output buffer. Under mod_perl, also sends HTTP headers if
they haven't been sent and calls C<< $r->rflush >> to flush the Apache buffer.
Flushing the initial bytes of output can make your servers appear more
responsive.

Attempts to flush the buffers are ignored within the context of a call to C<<
$m->scomp >> or when output is being stored in a scalar reference, as with the
C< { store =E<gt> \$out } > component call modifier.

C<< <%filter> >> blocks will process the output whenever the buffers are
flushed.  If C<autoflush> is on, your data may be filtered in  small pieces.

=item instance

=for html <a name="item_instance"></a>

This class method returns the C<Mason::Request> currently in use.  If called
when no Mason request is active it will return C<undef>.

If called inside a subrequest, it returns the subrequest object.

=item interp

=for html <a name="item_interp"></a>

Returns the Interp object associated with this request.

=item make_subrequest (comp => path, args => arrayref, other parameters)

=for html <a name="item_make_subrequest"></a>

This method creates a new Request object which inherits its parent's settable
properties, such as autoflush and out_method.  These values may be overridden
by passing parameters to this method.

The C<comp> parameter is required, while all other parameters are optional.  It
may be specified as an absolute path or as a path relative to the current
component.

See DEVEL<subrequests> for more information about subrequests.

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

C<notes()> is similar to the mod_perl method C<< $r->pnotes() >>.  The main
differences are that this C<notes()> can be used in a non-mod_perl environment,
and that its lifetime is tied to the I<Mason> request object, not the I<Apache>
request object.  In particular, a Mason subrequest has its own C<notes()>
structure, but would access the same C<< $r->pnotes() >> structure.

=item out (string)

=for html <a name="item_out"></a>

A synonym for C<$m-E<gt>print>.

=item print (string)

=for html <a name="item_print"></a>

Print the given I<string>. Rarely needed, since normally all text is just
placed in the component body and output implicitly. C<$m-E<gt>print> is useful
if you need to output something in the middle of a Perl block.

In 1.1 and on, C<print> and C<$r-E<gt>print> are remapped to C<$m-E<gt>print>,
so they may be used interchangeably. Before 1.1, one should only use
C<$m-E<gt>print>.

=item request_args

=for html <a name="item_request_args"></a>

Returns the arguments originally passed to the top level component (see
L<request_comp|Mason::Request/item_request_comp> for definition).  When called
in scalar context, a hash reference is returned. When called in list context, a
list of arguments (which may be assigned to a hash) is returned.

=item request_comp

=for html <a name="item_request_comp"></a>

Returns the component originally called in the request. Without autohandlers,
this is the same as the first component executed.  With autohandlers, this is
the component at the end of the C<$m-E<gt>call_next> chain.

=item request_depth

=for html <a name="request_depth"></a>

Returns the current size of the request/subrequest stack.  The lowest possible
value is 1, which indicates we are in the top-level request. A value of 2
indicates we are inside a subrequest of the top-level request, and so on.

=item scomp (comp, args...)

=for html <a name="item_scomp"></a>

Like L<comp|Mason::Request/item_comp>, but returns the component output as a
string instead of printing it. (Think sprintf versus printf.) The component's
return value is discarded.

=item subexec (comp, args...)

=for html <a name="item_subexec"></a>

This method creates a new subrequest with the specified top-level component and
arguments, and executes it. This is most often used to perform an "internal
redirect" to a new component such that autohandlers and dhandlers take effect.

=item time

=for html <a name="item_time"></a>

Returns the interpreter's notion of the current time (deprecated).

=back

=head1 APACHE-ONLY METHODS

These additional methods are available when running Mason with mod_perl and the
ApacheHandler.

=over

=item ah

=for html <a name="item_ah"></a>

Returns the ApacheHandler object associated with this request.

=item apache_req

=for html <a name="item_apache_req"></a>

Returns the Apache request object.  This is also available in the global C<$r>.

=item auto_send_headers

=for html <a name="item_auto_send_headers"></a>

True or false, default is true.  Indicates whether Mason should automatically
send HTTP headers before sending content back to the client. If you set to
false, you should call C<$r-E<gt>send_http_header> manually.

See DEVEL<sending HTTP headers> for more details about the automatic header
feature.

NOTE: This parameter has no effect under mod_perl-2, since calling
C<$r-E<gt>send_http_header> is no longer needed.

=back

=head1 CGI-ONLY METHODS

This additional method is available when running Mason with the CGIHandler
module.

=over

=item cgi_request

=for html <a name="item_cgi_request"></a>

Returns the Apache request emulation object, which is available as C<$r> inside
components.

See the L<CGIHandler docs|Mason::CGIHandler/"$r Methods"> for more details.

=back

=head1 APACHE- OR CGI-ONLY METHODS

This method is available when Mason is running under either the ApacheHandler
or CGIHandler modules.

=over 4

=item cgi_object

=for html <a name="item_cgi_object"></a>

Returns the CGI object used to parse any CGI parameters submitted to the
component, assuming that you have not changed the default value of the
ApacheHandler args_method parameter.  If you are using the 'mod_perl' args
method, then calling this method is a fatal error. See the
L<ApacheHandler|Mason::ApacheHandler> and L<CGIHandler|Mason::CGIHandler>
documentation for more details.

=item redirect ($url, [$status])

=for html <a name="item_redirect_url_status_"></a>

Given a url, this generates a proper HTTP redirect for that URL. It uses C<<
$m->clear_and_abort >> to clear out any previous output, and abort the request.
 By default, the status code used is 302, but this can be overridden by the
user.

Since this is implemented using C<< $m->abort >>, it will be trapped by an C<
eval {} > block.  If you are using an C< eval {} > block in your code to trap
errors, you need to make sure to rethrow these exceptions, like this:

  eval {
      ...
  };

  die $@ if $m->aborted;

  # handle other exceptions

=back

=head1 AUTHORS

Jonathan Swartz <swartz@pobox.com>, Dave Rolsky <autarch@urth.org>, Ken
Williams <ken@mathforum.org>

=head1 SEE ALSO

L<Mason|Mason>, L<Mason::Devel|Mason::Devel>,
L<Mason::Component|Mason::Component>

=cut
