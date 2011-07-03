package Mason::Request;
use Carp;
use File::Basename;
use Guard;
use Log::Any qw($log);
use Mason::Exceptions;
use Mason::TieHandle;
use Mason::Types;
use Mason::Moose;
use Scalar::Util qw(blessed reftype weaken);
use Try::Tiny;

my $default_out = sub { my ( $text, $self ) = @_; $self->result->_append_output($text) };
my $next_id = 0;

# Passed attributes
#
has 'interp'     => ( required => 1, weak_ref => 1 );
has 'out_method' => ( isa => 'Mason::Types::OutMethod', default => sub { $default_out }, coerce => 1 );

# Derived attributes
#
has 'buffer_stack'       => ( init_arg => undef, default => sub { [] } );
has 'declined'           => ( init_arg => undef, is => 'rw' );
has 'declined_paths'     => ( default => sub { {} } );
has 'go_result'          => ( init_arg => undef );
has 'id'                 => ( init_arg => undef, default => sub { $next_id++ } );
has 'output'             => ( init_arg => undef, default => '' );
has 'page'               => ( init_arg => undef );
has 'path_info'          => ( init_arg => undef, default => '' );
has 'request_args'       => ( init_arg => undef );
has 'request_code_cache' => ( init_arg => undef, default => sub { {} } );
has 'request_path'       => ( init_arg => undef );
has 'result'             => ( init_arg => undef, lazy_build => 1 );
has 'run_params'         => ( init_arg => undef );

# Globals, localized to each request
#
our ( $current_request, $current_buffer );
method current_request () { $current_request }

#
# BUILD
#

method BUILD ($params) {

    # Make a copy of params sans interp
    #
    $self->{orig_request_params} = $params;
    delete( $self->{orig_request_params}->{interp} );
}

method _build_result () {
    return $self->interp->result_class->new;
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

method add_cleanup ($code) {
    push( @{ $self->{cleanups} }, $code );
}

method cache () {
    die 'caching is now in the cache plugin (Mason::Plugin::Cache)';
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

method current_comp_class () {
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

method decline () {
    $self->declined(1);
    $self->clear_and_abort;
}

method filter () {
    $self->_apply_filters(@_);
}

method flush_buffer () {
    my $request_buffer = $self->_request_buffer;
    $self->out_method->( $$request_buffer, $self )
      if length $$request_buffer;
    $$request_buffer = '';
}

method go () {
    $self->clear_buffer;
    my %request_params = ( %{ $self->{orig_request_params} } );
    if ( ref( $_[0] ) eq 'HASH' ) {
        %request_params = ( %request_params, %{ shift(@_) } );
    }
    $self->{go_result} = $self->_run_subrequest( \%request_params, @_ );
    $self->abort();
}

method load ($path) {
    my $compc = $self->interp->load( $self->rel_to_abs($path) );
}

method log () {
    return $self->current_comp_class->cmeta->log();
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
    $path = join( "/", $self->current_comp_class->cmeta->dir_path, $path )
      unless substr( $path, 0, 1 ) eq '/';
    return $path;
}

method scomp () {
    my @params = @_;
    my $buf = $self->capture( sub { $self->comp(@params) } );
    return $buf;
}

method visit () {
    my $buf;
    my %request_params = ( %{ $self->{orig_request_params} }, out_method => \$buf );
    if ( ref( $_[0] ) eq 'HASH' ) {
        %request_params = ( %request_params, %{ shift(@_) } );
    }
    my $result = $self->_run_subrequest( \%request_params, @_ );
    $self->print($buf);
    return $result;
}

#
# MODIFIABLE METHODS
#

method cleanup_request () {
    $self->interp->_flush_load_cache();
    foreach my $cleanup ( @{ $self->{cleanups} } ) {
        try {
            $cleanup->($self);
        }
        catch {
            warn "error during request cleanup: $_";
        };
    }
}

method construct_page_component ($compc, $args) {
    return $compc->new( %$args, 'm' => $self );
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

method match_request_path ($request_path) {
    $self->interp->match_request_path->( $self, $request_path );
}

method run () {

    # Get path and either hash or hashref of arguments
    #
    my $request_path = shift;
    $self->interp->_assert_absolute_path($request_path);
    my $request_args;
    if ( @_ == 1 && reftype( $_[0] ) eq 'HASH' ) {
        $request_args = shift;
    }
    else {
        $request_args = {@_};
    }

    # Save off the requested path and args
    #
    $self->{request_path} = $request_path;
    $self->{request_args} = $request_args;

    # Localize current_request and current_buffer until end of scope. Use a guard
    # because 'local' doesn't work with the aliases inside components.
    #
    my $save_current_request = $current_request;
    my $save_current_buffer  = $current_buffer;
    scope_guard { $current_request = $save_current_request; $current_buffer = $save_current_buffer };
    $current_request = $self;
    $self->_push_buffer();

    # Clean up after request
    #
    scope_guard { $self->cleanup_request() };

    # Flush interp load cache
    #
    $self->interp->_flush_load_cache();

    # Check the static_source touch file, if it exists, before the
    # first component is loaded.
    #
    $self->interp->_check_static_source_touch_file();

    # Turn request path into a page component
    #
  match_request_path:
    my $page_path  = $self->match_request_path($request_path);
    my $page_compc = $self->interp->load($page_path);
    $log->debugf( "starting request with component '%s'", $page_path )
      if $log->is_debug;

    $self->catch_abort(
        sub {

            # Construct page component
            #
            my $page = $self->construct_page_component( $page_compc, $request_args );
            $self->{page} = $page;

            # Dispatch to page component, with 'print' tied to component output.
            #
            $self->with_tied_print( sub { $page->handle } );
        }
    );

    # If declined, retry match
    #
    if ( $self->declined ) {
        $self->declined(0);
        $self->{declined_paths}->{$page_path} = 1;
        goto match_request_path;
    }

    # If go() was called in this request, return the result of the subrequest
    #
    return $self->go_result if defined( $self->go_result );

    # Send output to its final destination
    #
    $self->flush_buffer;

    return $self->result;
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

method _apply_one_filter ($filter, $yield) {
    my $filtered_output;
    if ( ref($yield) ne 'CODE' ) {
        my $orig_yield = $yield;
        $yield = sub { $orig_yield };
    }
    if ( ref($filter) eq 'CODE' ) {
        local $_ = $yield->();
        $filtered_output = $filter->($_);
    }
    elsif ( blessed($filter) && $filter->can('apply_filter') ) {
        $filtered_output = $filter->apply_filter($yield);
    }
    else {
        die "'$filter' is neither a code ref nor a filter object";
    }
    return $filtered_output;
}

method _apply_filters () {
    my $yield = pop(@_);
    if ( ref($yield) ne 'CODE' ) {
        my $orig_yield = $yield;
        $yield = sub { $orig_yield };
    }
    if ( !@_ ) {
        return $yield->();
    }
    else {
        my $filter = pop(@_);
        return $self->_apply_filters( @_, sub { $self->_apply_one_filter( $filter, $yield ) } );
    }
}

method _apply_filters_to_output () {
    my $output_method = pop(@_);
    my $yield         = sub {
        my @args = @_;
        $self->capture( sub { $output_method->(@args) } );
    };
    my $filtered_output = $self->_apply_filters( @_, $yield );
    $self->print($filtered_output);
}

method _comp_not_found ($path) {
    croak sprintf( "could not find component for path '%s' - component root is [%s]",
        $path, join( ", ", @{ $self->interp->comp_root } ) );
}

method _current_buffer () {
    $self->{buffer_stack}->[-1];
}

method _pop_buffer () {
    pop( @{ $self->{buffer_stack} } );
    $current_buffer = $self->_current_buffer;
}

method _push_buffer () {
    my $s = '';
    push( @{ $self->{buffer_stack} }, \$s );
    $current_buffer = \$s;
}

method _request_buffer () {
    $self->{buffer_stack}->[0];
}

method _reset_next_id () {

    # for testing
    $next_id = 0;
}

method _run_subrequest () {
    my $request_params = shift(@_);
    my $path           = $self->rel_to_abs( shift(@_) );
    $self->interp->run( $request_params, $path, @_ );
}

__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

Mason::Request - Mason Request Class

=head1 SYNOPSIS

    $m->abort (...)
    $m->comp (...)
    etc.

=head1 DESCRIPTION

Mason::Request represents a single request for a page, and is the access point
for most Mason features not provided by syntactic tags.

A Mason request is created when you call C<< $interp->run >>, or in a web
environment, for each new web request. A new (sub-)request is also created when
you call L<visit> or L<go> on the current request.

Inside a component you can access the current request object via the global
C<$m>.  Outside of a component, you can use the class method
C<Mason::Request->current_request>.

=head1 COMPONENT PATHS

The methods L<comp>, L<comp_exists>, L<construct>, L<go>, L<load>, and L<visit>
take a component path argument. If the path does not begin with a '/', then it
is made absolute based on the current component path (using L<rel_to_abs>).

Component paths are like URL paths, and always use a forward slash (/) as the
separator, regardless of what your operating system uses.

=head1 PARAMETERS TO THE new() CONSTRUCTOR

These parameters would normally be passed in an initial hashref to  C<<
$interp->run >>, C<< $m->visit >>, or C<< $m->go >>.

=for html <a name="out_method" />

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

=for html <a name="abort" />

=over

=item abort ()

Ends the current request, finishing the page without returning through
components.

C<abort> is implemented by throwing an C<Mason::Exception::Abort> object and
can thus be caught by C<eval>. The C<aborted> method is a shortcut for
determining whether a caught error was generated by C<abort>.

=for html <a name="aborted" />

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

=for html <a name="add_cleanup" />

=item add_cleanup (code)

Add a code reference to be executed when the request is L<cleaned
up|/cleanup_request>.

=for html <a name="clear_and_abort" />

=item clear_and_abort ()

This method is syntactic sugar for calling C<clear_buffer()> and then
C<abort()>.  If you are aborting the request because of an error (or, in a web
environment, to do a redirect), you will often want to clear the buffer first
so that any output generated up to that point is not sent to the client.

=for html <a name="capture" />

=item capture (code)

Execute the I<code>, capturing and returning any Mason output instead of
outputting it. e.g. the following

    my $buf = $m->capture(sub { $m->comp('/foo') });

is equivalent to

    my $buf = $m->scomp('/foo');

=for html <a name="clear_buffer" />

=item clear_buffer ()

Clears the Mason output buffer. Any output sent before this line is discarded.
Useful for handling error conditions that can only be detected in the middle of
a request.

clear_buffer is, of course, thwarted by L<flush_buffer|/flush_buffer>.

=for html <a name="comp" />

=item comp (path[, params ...])

Creates a new instance of the component designated by I<path>, and calls its
C<main> method. I<params>, if any, are passed to the constructor.

The C<< <& &> >> tag provides a shortcut for C<$m-E<gt>comp>.

=for html <a name="comp_exists" />

=item comp_exists (path)

Makes the component I<path> absolute if necessary, and calls L<Interp
comp_exists|Mason::Interp/comp_exists> to determine whether a component exists
at that path.

=for html <a name="current_comp_class" />

=item current_comp_class ()

Returns the current component class. This is determined by walking up the Perl
caller() stack until the first Mason::Component subclass is found.

=for html <a name="current_request" />

=item current_request ()

This class method returns the C<Mason::Request> currently in use.  If called
when no Mason request is active it will return C<undef>.

=for html <a name="construct" />

=item construct (path[, params ...])

Constructs and return a new instance of the component designated by I<path>.
I<params>, if any, are passed to the constructor. Throws an error if I<path>
does not exist.

=for html <a name="decline" />

=item decline ()

Clears the output buffer and tries the current request again, but acting as if
the previously chosen page component(s) do not exist.

For example, if the following components exist:

    /news/sports.mc
    /news/dhandler.mc
    /dhandler.mc

then a request for path C</news/sports> will initially resolve to
C</news/sports.mc>.  A call to C<< $m->decline >> would restart the request and
resolve to C</news/dhandler.mc>, a second C<< $m->decline >> would resolve to
C</dhandler.mc>, and a third would throw a "not found" error.

=for html <a name="flush_buffer" />

=item filter (filter_expr, [filter_expr...], string|coderef)

Applies one or more filters to a string or to a coderef that returns a string.

    my $filtered_string = $m->filter($.Trim, $.NoBlankLines, $string);

=item flush_buffer ()

Flushes the main output buffer. Anything currently in the buffer is sent to the
request's L<out_method|/out_method>.

Note that anything output within a C<< $m->scomp >> or C<< $m->capture >> will
not have made it to the main output buffer, and thus cannot be flushed.

=for html <a name="go" />

=item go ([request params], path, args...)

Performs an internal redirect. Clears the output buffer, runs a new request for
the given I<path> and I<args>, and then L<aborts|/abort> when that request is
done.

The first argument may optionally be a hashref of parameters which are passed
to the C<Mason::Request> constructor.

See also L<visit|/visit>.

=for html <a name="interp" />

=item interp ()

Returns the L<Interp|Mason::Interp> object associated with this request.

=for html <a name="load" />

=item load (path)

Makes the component I<path> absolute if necessary, and calls L<Interp
load|Mason::Interp/load> to load the component class associated with the path.

=for html <a name="log" />

=item log ()

Returns a C<Log::Any> logger with a log category specific to the current
component.  The category for a component "/foo/bar" would be
"Mason::Component::foo::bar".

=for html <a name="notes" />

=item notes ([key[, value]])

The C<notes()> method provides a place to store application data between
components - essentially, a hash which persists for the duration of the
request.

C<notes($key, $value)> stores a new entry in the hash; C<notes($key)> returns a
previously stored value; and C<notes()> without any arguments returns a
reference to the entire hash of key-value pairs.

Consider storing this kind of data in a read-write attribute of the page
component.

=for html <a name="print" />

=item print (string)

Add the given I<string> to the Mason output buffer. This happens implicitly for
all content placed in the main component body.

=for html <a name="page" />

=item page ()

Returns the page component originally called in the request.

=for html <a name="path_info" />

=item path_info ()

Returns the remainder of the request path beyond the path of the page
component, with no leading slash. e.g. If a request for '/foo/bar/baz' resolves
to "/foo.mc", the path_info is "bar/baz". For an exact match, it will contain
the empty string (never undef), so you can determine whether there's a
path_info with

    if ( length($m->path_info) )

=for html <a name="rel_to_abs" />

=item rel_to_abs (path)

Converts a component I<path> to absolute form based on the current component,
if it does not already begin with a '/'.

=for html <a name="request_args" />

=item request_args ()

Returns the original hashref of arguments passed to the request, e.g. via C<<
$interp->run >>.

=for html <a name="request_path" />

=item request_path ()

Returns the original path passed to the request, e.g. in C<< $interp->run >>.

=for html <a name="scomp" />

=item scomp (comp, args...)

Like L<comp|Mason::Request/item_comp>, but returns the component output as a
string instead of printing it. (Think sprintf versus printf.)

=for html <a name="visit" />

=item visit ([request params], path, args...)

Performs a subrequest with the given I<path> and I<args>, with output being
sent to the current output buffer.

The first argument may optionally be a hashref of parameters which are passed
to the C<Mason::Request> constructor. e.g. to capture the output of the
subrequest:

    $m->visit({out_method => \my $buffer}, ...);

See also L<go|/go>.

=back

=head1 MODIFIABLE METHODS

These methods are not intended to be called externally, but may be useful to
modify with method modifiers in plugins and subclasses. Their APIs will be kept
as stable as possible.

=for html <a name="cleanup_request" />

=over

=item cleanup_request ()

A place to perform cleanup duties when the request finishes or dies with an
error, even if the request object is not immediately destroyed. Includes
anything registered with L<add_cleanup|/add_cleanup>.

=for html <a name="construct_page_component" />

=item construct_page_component ($compc, $args)

Constructs the page component of class I<$compc>, with hashref of constructor
arguments I<$args>.

=for html <a name="match_request_path" />

=item match_request_path ($request_path)

Given a top level I<$request_path>, return a corresponding component path or
undef if none was found. Search includes dhandlers and index files. See
L<Mason::Manual::RequestDispatch>.

=for html <a name="run" />

=item run (request_path, args)

Runs the request with I<request_path> and I<args>, where the latter can be
either a hashref or a hash. This is generally called via << $interp->run >>.

=for html <a name="with_tied_print" />

=item with_tied_print ($code)

Execute the given I<$code> with the current selected filehandle ('print') tied
to the Mason output stream. You could disable the filehandle selection by
overriding this to just call I<$code>.

=back

=cut
