package Mason::Plugin::LvalueAttributes::Interp;
use Mason::PluginRole;

after 'modify_loaded_class' => sub {
    my ( $self, $compc ) = @_;
    $self->_add_lvalue_attribute_methods($compc);
};

sub _add_lvalue_attribute_methods {
    my ( $self, $class ) = @_;

    my @attrs = $class->meta->get_all_attributes();
    foreach my $attr (@attrs) {
        if ( $attr->_is_metadata eq 'rw' ) {
            my $name = $attr->name;
            $class->meta->add_method(
                $name,
                sub : lvalue {
                    if ( defined( $_[1] ) ) {
                        $_[0]->{$name} = $_[1];
                    }
                    $_[0]->{$name};
                }
            );
        }
    }
}

1;
