# Copyright (c) 1998-2005 by Jonathan Swartz. All rights reserved.
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.

package Mason::Compiler;
use Data::Dumper;
use File::Basename;
use File::Path;
use File::Slurp;
use Mason::Compilation;
use Mason::Types;
use Mason::Util qw(checksum);
use Method::Signatures::Simple;
use Moose;
use strict;
use warnings;

# Passed attributes
has 'allow_globals' => ( is => 'ro', default => sub { [] } );
has 'compilation_class' => ( is => 'ro', default => 'Mason::Compilation' );
has 'default_escape_flags' => ( is => 'ro', default => sub { [] } );
has 'internal_component_regex' =>
( is => 'ro', isa => 'Mason::Types::RegexpRefOrStr', default => sub { qr/\.mi$/ }, coerce => 1 );

has 'no_source_line_numbers' => ( is => 'ro' );
has 'perltidy_object_files'  => ( is => 'ro' );
has 'valid_flags'            => ( is => 'ro', default => sub { ['extends'] } );

# Derived attributes
has 'block_regex'      => ( is => 'ro', lazy_build => 1, init_arg => undef );
has 'block_types'      => ( is => 'ro', lazy_build => 1, init_arg => undef );
has 'compiler_id'      => ( is => 'ro', lazy_build => 1, init_arg => undef );
has 'valid_flags_hash' => ( is => 'ro', lazy_build => 1, init_arg => undef );

# Default list of blocks - may be augmented in subclass
#
method _build_block_types () {
    return [qw(class doc flags filter init perl text)];
}

method _build_block_regex () {
    my $re = join '|', @{ $self->block_types };
    return qr/$re/i;
}

method _build_compiler_id () {

    # TODO - collect all attributes automatically
    my @vals = ( 'Mason::VERSION', $Mason::VERSION );
    my @attrs = qw(default_escape_flags use_source_line_numbers);
    foreach my $k (@attrs) {
        push @vals, $k, $self->{$k};
    }
    my $dumped_vals = Data::Dumper->new( \@vals )->Indent(0)->Dump;
    return checksum($dumped_vals);
}

method _build_valid_flags_hash () {
    return { map { ( $_, 1 ) } @{ $self->valid_flags } };
}

# Like [a-zA-Z_] but respects locales
method escape_flag_regex () {
    return qr/[[:alpha:]_]\w*/;
}

method compile ( $interp, $source_file, $path ) {
    my $compilation = $self->compilation_class->new(
        interp      => $interp,
        source_file => $source_file,
        path        => $path,
        compiler    => $self
    );
    return $compilation->compile();
}

method compile_to_file ( $interp, $source_file, $path, $dest_file ) {

    # We attempt to handle several cases in which a file already exists
    # and we wish to create a directory, or vice versa.  However, not
    # every case is handled; to be complete, mkpath would have to unlink
    # any existing file in its way.
    #
    if ( defined $dest_file && !-f $dest_file ) {
        my ($dirname) = dirname($dest_file);
        if ( !-d $dirname ) {
            unlink($dirname) if ( -e _ );
            mkpath( $dirname, 0, 0775 );
        }
        rmtree($dest_file) if ( -d $dest_file );
    }
    my $object_contents = $self->compile( $interp, $source_file, $path );
    if ( my $perltidy_options = $self->perltidy_object_files ) {
        require Perl::Tidy;
        my $argv = ( $perltidy_options eq '1' ? '' : $perltidy_options );
        my $source = $object_contents;
        Perl::Tidy::perltidy(
            'perltidyrc' => '/dev/null',
            source       => \$source,
            destination  => \$object_contents,
            argv         => $argv
        );
    }
    write_file( $dest_file, $object_contents );
}

method is_external_comp_path ($path) {
    return $path =~ /\.(pm|m)$/ ? 1 : 0;
}

1;
