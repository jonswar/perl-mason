package Mason::Plugin::PSGIHandler::Interp;
use Mason::Plugin::PSGIHandler::PlackRequest;
use Mason::PluginRole;
use Try::Tiny;
use Mason::Plugin::PSGIHandler::Extra::StackTrace;

method handle_psgi ($env) {
    local $Plack::Middleware::StackTrace::StackTraceClass =
      'Mason::Plugin::PSGIHandler::Extra::StackTrace';
    my $req      = Mason::Plugin::PSGIHandler::PlackRequest->new($env);
    my $response = try {
        $self->run( { req => $req }, $self->psgi_comp_path($req), $self->psgi_parameters($req) )
          ->plack_response;
    }
    catch {
        my $err = $_;
        if ( blessed($err) && $err->isa('Mason::Exception::TopLevelNotFound') ) {
            Mason::Plugin::PSGIHandler::PlackResponse->new(404);
        }
        else {
            local $SIG{__DIE__} = undef;
            die $err;
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
