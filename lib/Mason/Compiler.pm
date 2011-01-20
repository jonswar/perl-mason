# Copyright (c) 1998-2005 by Jonathan Swartz. All rights reserved.
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.

package Mason::Compiler;
use Data::Dumper;
use File::Basename;
use File::Path;
use Mason::Compilation;
use Mason::Types;
use Mason::Util qw(checksum write_file);
use Mason::Moose;

# Passed attributes
has 'interp'                 => ( required => 1, weak_ref => 1 );
has 'no_source_line_numbers' => ( );

# Derived attributes
has 'compiler_id'         => ( lazy_build => 1, init_arg => undef );
has 'named_block_regex'   => ( lazy_build => 1, init_arg => undef );
has 'named_block_types'   => ( lazy_build => 1, init_arg => undef );
has 'unnamed_block_regex' => ( lazy_build => 1, init_arg => undef );
has 'unnamed_block_types' => ( lazy_build => 1, init_arg => undef );
has 'valid_flags'         => ( lazy_build => 1, init_arg => undef );
has 'valid_flags_hash'    => ( lazy_build => 1, init_arg => undef );

method _build_compiler_id () {

    # TODO - collect all attributes automatically
    my @vals = ( 'Mason::VERSION', $Mason::VERSION );
    my @attrs = qw(default_escape_flags no_source_line_numbers);
    foreach my $k (@attrs) {
        push @vals, $k, $self->{$k};
    }
    my $dumped_vals = Data::Dumper->new( \@vals )->Indent(0)->Dump;
    return checksum($dumped_vals);
}

method _build_named_block_regex () {
    my $re = join '|', @{ $self->named_block_types };
    return qr/$re/i;
}

method _build_named_block_types () {
    return [qw(after augment around before filter method)];
}

method _build_unnamed_block_regex () {
    my $re = join '|', @{ $self->unnamed_block_types };
    return qr/$re/i;
}

method _build_unnamed_block_types () {
    return [qw(args class doc flags init perl shared text)];
}

method _build_valid_flags () {
    return [qw(extends)];
}

method _build_valid_flags_hash () {
    return { map { ( $_, 1 ) } @{ $self->valid_flags } };
}

method compile ( $source_file, $path ) {
    my $compilation = $self->interp->compilation_class->new(
        source_file => $source_file,
        path        => $path,
        compiler    => $self
    );
    return $compilation->compile();
}

method compile_to_file ( $source_file, $path, $object_file ) {

    # We attempt to handle several cases in which a file already exists
    # and we wish to create a directory, or vice versa.  However, not
    # every case is handled; to be complete, mkpath would have to unlink
    # any existing file in its way.
    #
    if ( defined $object_file && !-f $object_file ) {
        my ($dirname) = dirname($object_file);
        if ( !-d $dirname ) {
            unlink($dirname) if ( -e _ );
            mkpath( $dirname, 0, 0775 );
        }
        rmtree($object_file) if ( -d $object_file );
    }
    my $object_contents = $self->compile( $source_file, $path );

    $self->write_object_file( $object_file, $object_contents );
}

method write_object_file ($object_file, $object_contents) {
    write_file( $object_file, $object_contents );
}

method is_external_comp_path ($path) {
    return ( $path =~ /\.(pm|m)$/ ) ? 1 : 0;
}

method is_pure_perl_comp_path ($path) {
    return ( $path =~ /\.pm$/ ) ? 1 : 0;
}

__PACKAGE__->meta->make_immutable();

1;

# ABSTRACT: Mason Compiler
__END__

=head1 DESCRIPTION

Compiler is the Mason object responsible for compiling components into Perl
classes. Each Interp creates a single persistent Compiler. The Compiler in turn
creates a Compilation object to compile each component.

=head1 PARAMETERS TO THE new() CONSTRUCTOR

=over

=item no_source_line_numbers

Do not put in source line number comments when generating code.  Setting this
to true will cause error line numbers to reflect the real object file, rather
than the source component.

=back

=head1 ACCESSOR METHODS

All of the above properties have standard read-only accessor methods of the
same name.

