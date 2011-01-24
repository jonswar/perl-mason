package Mason::Plugin::Defer::Request;
use Mason::PluginRole;

has 'defers' => (is => 'rw', init_arg => undef, default => sub { [] });

before 'flush_buffer' => sub {
    my $self = shift;
    $self->_apply_defers_to_request_buffer();
};

method defer ($code) {
    my $marker = $self->interp->_construct_distinct_string();
    push( @{ $self->{defers} }, { marker => $marker, code => $code } );
    return $marker;
}

method _apply_defers_to_request_buffer () {
    if ( my @defers = @{ $self->{defers} } ) {
        my $request_buffer = ${ $self->_request_buffer };
        foreach my $defer (@defers) {
            my $subst = $defer->{marker};
            my $repl  = $defer->{code}->();
            $request_buffer =~ s/\Q$subst\E/$repl/;
        }
        ${ $self->_request_buffer } = $request_buffer;
    }
}

1;
