package Mason::Plugin::PSGIHandler::PlackRequest;
use Method::Signatures::Simple;
use Moose;
extends 'Plack::Request';

has 'mason_comp_path'  => (is => 'ro', init_arg => undef, lazy_build => 1);
has 'mason_parameters' => (is => 'ro', init_arg => undef, lazy_build => 1);

method _build_mason_comp_path () {
    my $comp_path = $self->path;
    $comp_path = "/$comp_path" if substr( $comp_path, 0, 1 ) ne '/';
    return $comp_path;
}

method _build_mason_parameters () {
    return $self->parameters;
}

1;
