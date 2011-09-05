package Mason::Test::RootClass::Interp;
use Moose;
extends 'Mason::Interp';

before 'run' => sub {
    print STDERR "starting interp run\n";
};

1;
