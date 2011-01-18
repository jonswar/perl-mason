package Mason::Test::Plugins::Notify::Compilation;
use Moose::Role;
use namespace::autoclean;

before 'compile' => sub {
    my ($self) = @_;
    print STDERR "starting compilation compile - " . $self->path . "\n";
};

1;
