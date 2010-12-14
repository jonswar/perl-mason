package Mason::Test::Plugins::Notify::Compilation;
use Moose::Role;
use strict;
use warnings;

before 'compile' => sub {
    my ($self) = @_;
    print STDERR "starting compilation compile - " . $self->path . "\n";
};

1;
