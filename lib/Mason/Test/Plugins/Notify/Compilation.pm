package Mason::Test::Plugins::Notify::Compilation;
use Mason::PluginRole;

before 'compile' => sub {
    my ($self) = @_;
    print STDERR "starting compilation compile - " . $self->path . "\n";
};

1;
