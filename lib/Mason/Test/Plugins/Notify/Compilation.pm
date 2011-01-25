package Mason::Test::Plugins::Notify::Compilation;
use Mason::PluginRole;

before 'parse' => sub {
    my ($self) = @_;
    print STDERR "starting compilation parse - " . $self->path . "\n";
};

1;
