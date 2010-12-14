package Mason::Plugin::TidyObjectFiles::Compiler;
use Perl::Tidy;
use strict;
use warnings;

has 'tidy_object_files' => ( is => 'ro' );

around 'write_object_file' => sub {
    my ( $orig, $self, $object_file, $object_contents ) = @_;

    if ( my $tidy_options = $self->tidy_object_files ) {
        my $argv = ( $tidy_options eq '1' ? '' : $tidy_options );
        my $source = $object_contents;
        Perl::Tidy::perltidy(
            'perltidyrc' => '/dev/null',
            source       => \$source,
            destination  => \$object_contents,
            argv         => $argv
        );
        $self->$orig( $object_file, $object_contents );
    }
};

1;
