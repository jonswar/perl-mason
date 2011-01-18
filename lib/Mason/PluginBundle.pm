package Mason::PluginBundle;
use Moose::Role;
use Method::Signatures::Simple;
use namespace::autoclean;

method expand_to_plugins ($bundle_class:) {
    return @{ Mason::PluginManager->process_plugins_list( [ $bundle_class->provides_plugins ] ) };
}

requires 'provides_plugins';

1;
