package Mason::Test::Plugins::Notify::Interp;
use Moose::Role;
use namespace::autoclean;

before 'run' => sub {
    print STDERR "starting interp run\n";
};

1;
