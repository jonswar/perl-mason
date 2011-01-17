package Mason::Plugin::PSGIHandler::Interp;
use Mason::Plugin::PSGIHandler::PlackRequest;
use Method::Signatures::Simple;
use Moose::Role;

method handle_psgi ($env) {
    my $req      = Mason::Plugin::PSGIHandler::PlackRequest->new($env);
    my $result   = $self->run( { req => $req }, $req->mason_comp_path, $req->mason_parameters );
    my $response = $result->plack_response;
    $response->content( $result->output );
    return $response->finalize;
}

1;
