package Mason::Test::Plugins::Notify::Compiler;
use Moose::Role;
use namespace::autoclean;

before 'compile' => sub {
    my ( $self, $source_file, $path ) = @_;
    print STDERR "starting compiler compile - $path\n";
};

1;
