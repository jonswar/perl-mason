package Mason::Plugin::DollarDot::Compilation;
use Moose::Role;
use strict;
use warnings;

after 'process_perl_code' => sub {
    my ( $self, $coderef ) = @_;
    $$coderef =~ s/ \$\.([^\W\d]\w*) / \$self->$1 /gx;
};

1;
