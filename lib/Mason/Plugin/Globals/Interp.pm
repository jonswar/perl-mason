package Mason::Plugin::Globals::Interp;
use Carp;
use Mason::PluginRole;

# Passed attributes
#
has 'allow_globals'   => ( isa => 'ArrayRef[Str]' );
has 'globals_package' => ( isa => 'Str', lazy_build => 1 );

# Derived attributes
#
has 'allowed_globals_hash' => ( init_arg => undef, lazy_build => 1);

method _build_allowed_globals_hash () {
    my @canon_globals = map { join( "", $self->_parse_global_spec($_) ) } @{ $self->allow_globals };
    return { map { ( $_, 1 ) } @canon_globals };
}

method _build_globals_package () {
    return "MG" . $self->count;
}

method _parse_global_spec () {
    my $spec = shift;
    my ( $sigil, $name ) = ( $spec =~ s/^([\$@%])// ) ? ( $1, $spec ) : ( '$', $spec );
    return ( $sigil, $name );
}

method set_global () {
    my ( $spec, @values ) = @_;
    croak "set_global expects a variable name and one or more values" unless @values;
    my ( $sigil, $name ) = $self->_parse_global_spec($spec);
    croak "${sigil}${name} is not in the allowed globals list"
      unless $self->allowed_globals_hash->{"${sigil}${name}"};

    my $varname = sprintf( "%s::%s", $self->globals_package, $name );
    no strict 'refs';
    no warnings 'once';
    if ( $sigil eq '$' ) {
        $$varname = $values[0];
    }
    elsif ( $sigil eq '@' ) {
        @$varname = @values;
    }
    else {
        %$varname = @values;
    }
}

1;
