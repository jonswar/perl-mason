package Mason::Test::Plugins::Notify::Interp;
use Mason::PluginRole;

before 'run' => sub {
    print STDERR "starting interp run\n";
};

1;
