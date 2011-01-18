package Mason::Plugin::TidyObjectFiles::Compiler;
use Moose::Role;
use Perl::Tidy;
use namespace::autoclean;

has 'tidy_options' => ( is => 'ro' );

around 'write_object_file' => sub {
    my ( $orig, $self, $object_file, $object_contents ) = @_;

    my $argv = $self->tidy_options || '';
    my $tidied_object_contents;
    Perl::Tidy::perltidy(
        'perltidyrc' => '/dev/null',
        source       => \$object_contents,
        destination  => \$tidied_object_contents,
        prefilter    => sub { $self->prefilter( $_[0] ) },
        postfilter   => sub { $self->postfilter( $_[0] ) },
        argv         => $argv
    );
    $tidied_object_contents =~ s/^\s*(\#line .*)/$1/mg;
    $self->$orig( $object_file, $tidied_object_contents );
};

sub prefilter {
    my $self = shift;
    $_ = $_[0];

    # Turn method into sub
    s/^method (.*)/sub $1 \#__METHOD/gm;

    return $_;
}

sub postfilter {
    my $self = shift;
    $_ = $_[0];

    # Turn sub back into method
    s/^sub (.*?)\s* \#__METHOD/method $1/gm;

    return $_;
}

1;
