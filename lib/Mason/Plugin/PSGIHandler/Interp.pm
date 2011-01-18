package Mason::Plugin::PSGIHandler::Interp;
use Mason::Plugin::PSGIHandler::PlackRequest;
use Method::Signatures::Simple;
use Moose::Role;
use namespace::autoclean;

method handle_psgi ($env) {
    my $req = Mason::Plugin::PSGIHandler::PlackRequest->new($env);
    my $result =
      $self->run( { req => $req }, $self->psgi_comp_path($req), $self->psgi_parameters($req) );
    my $response = $result->plack_response;
    $response->content( $result->output );
    return $response->finalize;
}

method psgi_comp_path ($req) {
    my $comp_path = $req->path;
    $comp_path = "/$comp_path" if substr( $comp_path, 0, 1 ) ne '/';
    return $comp_path;
}

method psgi_parameters ($req) {
    return $req->parameters;
}

1;
