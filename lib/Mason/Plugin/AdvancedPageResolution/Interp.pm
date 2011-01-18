package Mason::Plugin::AdvancedPageResolution::Interp;
use Method::Signatures::Simple;
use Moose::Role;
use namespace::autoclean;

# Passed attributes
#
has 'dhandler_names'  => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'index_names'     => ( isa => 'ArrayRef[Str]', lazy_build => 1 );
has 'page_extensions' => ( isa => 'ArrayRef[Str]', default => sub { [ '.pm', '.m' ] } );

# Derived attributes
#
has 'autobase_or_dhandler_regex'    => ( lazy_build => 1, init_arg => undef );

method _build_autobase_or_dhandler_regex () {
    my $regex = '(' . join( "|", @{ $self->autobase_names }, @{ $self->dhandler_names } ) . ')$';
    return qr/$regex/;
}

method _build_dhandler_names () {
    return [ map { "dhandler" . $_ } @{ $self->page_extensions } ];
}

method _build_index_names () {
    return [ map { "index" . $_ } @{ $self->page_extensions } ];
}

1;
