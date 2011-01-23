package Mason::Test::Plugins::Notify::Interp;
use Mason::PluginRole;

before 'run' => sub {
    print STDERR "starting interp run\n";
};

before 'compile' => sub {
    my ( $self, $source_file, $path ) = @_;
    print STDERR "starting interp compile - $path\n";
};

1;
