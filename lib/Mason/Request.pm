package Mason::Request;
use autodie qw(:all);
use Carp;
use File::Basename;
use Guard;
use Log::Any qw($log);
use Mason::Exceptions;
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
has 'out_method' => ( isa => 'Mason::Types::OutMethod', default => sub { $default_out }, coerce => 1 );
has 'declined_paths' => ( default => sub { {} } );

# Derived attributes
has 'buffer_stack'       => ( init_arg => undef );
has 'count'              => ( init_arg => undef );
has 'path_info'          => ( init_arg => undef, default => '' );
has 'page'               => ( init_arg => undef );
has 'request_args'       => ( init_arg => undef );
has 'request_code_cache' => ( init_arg => undef );
has 'request_path'       => ( init_arg => undef );

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
    my ( $compc, $path_info ) = $self->resolve_request_path_to_component($path);
    if ( !defined($compc) ) {
        croak sprintf( "could not find top-level component for path '%s' - component root is [%s]",
            $path, join( ", ", @{ $self->interp->comp_root } ) );
    }

    $self->comp_not_found($path) if !defined($compc);
    $self->{path_info} = $path_info;

    my $page = $compc->new( @_, 'm' => $self );
    $self->{page} = $page;
    $log->debugf( "starting request for '%s'", $page->title )
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

    # Send output to its final destination
    #
    $self->flush_buffer;

    # Return aborted value or result.
    #
    return $self->aborted($err) ? $err->aborted_value : $retval;
}

# Given /foo/bar, look for (by default):
#   /foo/bar.{pm,m},
#   /foo/bar/index.{pm,m},
#   /foo/bar/dhandler.{pm,m},
#   /foo.{pm,m}
#   /dhandler.{pm,m}
#
method resolve_request_path_to_component ($request_path) {
    my $interp               = $self->interp;
    my @dhandler_subpaths    = map { "/$_" } @{ $interp->dhandler_names };
    my @index_subpaths       = map { "/$_" } @{ $interp->index_names };
    my @top_level_extensions = @{ $interp->top_level_extensions };
    my $autobase_or_dhandler = $interp->autobase_or_dhandler_regex;
    my $path                 = $request_path;
    my $path_info            = '';
    my $declined_paths       = $self->declined_paths;

    while (1) {
        my @candidate_paths =
            ( $path eq '/' )
          ? ( @index_subpaths, @dhandler_subpaths )
          : (
            ( grep { !/$autobase_or_dhandler/ } map { $path . $_ } @top_level_extensions ),
            ( map { $path . $_ } ( @index_subpaths, @dhandler_subpaths ) )
          );
        foreach my $candidate_path (@candidate_paths) {
            next if $declined_paths->{$candidate_path};
            my $compc = $interp->load($candidate_path);
            if ( defined($compc) && $compc->comp_is_external ) {
                return ( $compc, $path_info );
            }
        }
        return () if $path eq '/';
        my $name = basename($path);
        $path_info = length($path_info) ? "$name/$path_info" : $name;
        $path = dirname($path);
        @index_subpaths = ();    # only match in same directory
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

method call_next () {
    return $self->current_comp_class->comp_inner();
}

# Determine current comp class based on caller() stack.
#
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
    return $self->fetch_compc($path) ? 1 : 0;
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

method comp () {
    $self->fetch_comp_or_die(@_)->main();
}

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

method visit () {
    my $retval = $self->interp->run( { out_method => \my $buf }, @_ );
    $self->print($buf);
    return $retval;
}

method go () {
    $self->clear_buffer;
    my $retval = $self->interp->run( { out_method => $self->out_method }, @_ );
    $self->abort($retval);
}

method decline () {
    $self->go( { declined_paths => { %{ $self->declined_paths }, $self->page->comp_path => 1 } },
        $self->request_path, @{ $self->request_args } );
}

method clear_buffer () {
    foreach my $buffer ( @{ $self->buffer_stack } ) {
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

Ends the current request, finishing the page without returning through
components. The optional argument specifies the return value from
C<Interp::run>; in a web environment, this ultimately becomes the HTTP status
code.

C<abort> is implemented by throwing an Mason::Exception::Abort object and can
thus be caught by eval(). The C<aborted> method is a shortcut for determining
whether a caught error was generated by C<abort>.

=item clear_and_abort ([return value])

This method is syntactic sugar for calling C<clear_buffer()> and then
C<abort()>.  If you are aborting the request because of an error, you will
often want to clear the buffer first so that any output generated up to that
point is not sent to the client.

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

=item cache ([params])

C<$m-E<gt>cache> returns a new L<CHI object|CHI> with a namespace specific to
this component. Any parameters are combined with
L<Interp/chi_default_parameters> and passed along to the
L<Interp/chi_root_class> constructor.

=item capture (scalarref, code)

Execute the I<code>, capturing any Mason output into the I<scalarref>. e.g.

    $m->capture(\my $buf, sub { $m->comp(...) });
    # $buf contains the output of the $m->comp call

=item clear_buffer

Clears the Mason output buffer. Any output sent before this line is discarded.
Useful for handling error conditions that can only be detected in the middle of
a request.

clear_buffer is, of course, thwarted by L</flush_buffer>.

=item comp (path, args...)

Calls the component designated by I<path>. Any additional arguments are passed
as attributes to the new component instance.

I<path> may be an absolute or relative component path, in which case it will be
passed to L</fetch_comp>; or it may be a component class such as is returned by
L</fetch_comp>.

The <& &> tag provides a convenient shortcut for C<$m-E<gt>comp>.

=item comp_exists (path)

Returns 1 if I<path> is the path of an existing component, 0 otherwise.

Depending on implementation, <comp_exists> may try to load the component
referred to by the path, and may throw an error if the component contains a
syntax error.

=item count

Returns the number of this request, which is unique for a given request and
interpreter.

=item current_comp_class

Returns the current component class.

=item current_request

This class method returns the C<Mason::Request> currently in use.  If called
when no Mason request is active it will return C<undef>.

=item decline

Clears the output buffer and issues the current request again, but acting as if
the previously chosen page component(s) do not exist.

For example, if the following components exist:

    /news/sports.m
    /news/dhandler.m
    /dhandler.m

then a request for path C</news/sports> will initially resolve to
C</news/sports.m>.  A call to C<< $m->decline >> would restart the request and
resolve to C</news/dhandler.m>, a second C<< $m->decline >> would resolve to
C</dhandler.m>, and a third would throw a "not found" error.

=item fetch_comp (path)

Return a new instance of the component at I<path>.

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

Returns the Interp object associated with this request.

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

=head1 AUTHORS

Jonathan Swartz <swartz@pobox.com>

=head1 SEE ALSO

L<Mason|Mason>

=cut
