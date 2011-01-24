package Mason::Plugin::PSGIHandler::Interp;
use Mason::Plugin::PSGIHandler::PlackRequest;
use Mason::PluginRole;
use Try::Tiny;

method handle_psgi ($env) {
    my $req      = Mason::Plugin::PSGIHandler::PlackRequest->new($env);
    my $response = try {
        $self->run( { req => $req }, $self->psgi_comp_path($req), $self->psgi_parameters($req) )
          ->plack_response;
    }
    catch {
        if ( blessed($_) && $_->isa('Mason::Exception::TopLevelNotFound') ) {
            Mason::Plugin::PSGIHandler::PlackResponse->new(404);
        }
        else {
            die $_;
        }
    };
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
