package Mason::Plugin::TidyObjectFiles::Compiler;
use Moose::Role;
use Perl::Tidy;
use strict;
use warnings;

has 'tidy_options' => ( is => 'ro' );

around 'write_object_file' => sub {
    my ( $orig, $self, $object_file, $object_contents ) = @_;

    my $argv = $self->tidy_options || '';
    my $tidied_object_contents;
    Perl::Tidy::perltidy(
        'perltidyrc' => '/dev/null',
        source       => \$object_contents,
        destination  => \$tidied_object_contents,
        argv         => $argv
    );
    $tidied_object_contents =~ s/^\s*(\#line .*)/$1/mg;
    $self->$orig( $object_file, $tidied_object_contents );
};

1;
