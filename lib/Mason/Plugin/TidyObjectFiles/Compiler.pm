package Mason::Plugin::TidyObjectFiles::Compiler;
use Moose::Role;
use Perl::Tidy;
use strict;
use warnings;

has 'tidy_options' => ( is => 'ro' );

around 'write_object_file' => sub {
    my ( $orig, $self, $object_file, $object_contents ) = @_;

    my $argv = $self->tidy_options || '';
    my $source = $object_contents;
    Perl::Tidy::perltidy(
        'perltidyrc' => '/dev/null',
        source       => \$source,
        destination  => \$object_contents,
        argv         => $argv
    );
    $self->$orig( $object_file, $object_contents );
};

1;
