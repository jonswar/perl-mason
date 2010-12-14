package Mason::Test::Plugins::Notify::Interp;
use Moose::Role;
use strict;
use warnings;

before 'run' => sub {
    print STDERR "starting interp run\n";
};

1;
