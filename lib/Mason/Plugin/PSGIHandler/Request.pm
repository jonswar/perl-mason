package Mason::Plugin::PSGIHandler::Request;
use Mason::Plugin::PSGIHandler::PlackResponse;
use Method::Signatures::Simple;
use Moose::Role;

has 'req' => (required => 1, isa => 'Object');
has 'res' => (lazy_build => 1);

method _build_res () {
    return Mason::Plugin::PSGIHandler::PlackResponse->new();
}

around 'run' => sub {
    my $orig = shift;
    my $self = shift;

    my $result = $self->$orig(@_);
    $self->res->status(200) if !$self->res->status;
    $result->plack_response( $self->res );
    return $result;
};

before 'abort' => sub {
    my ( $self, $retval ) = @_;
    $self->res->status($retval) if defined($retval);
};

method redirect  () {
    $self->res->redirect(@_);
    $self->clear_and_abort();
}

1;
