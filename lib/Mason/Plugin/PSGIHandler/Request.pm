package Mason::Plugin::PSGIHandler::Request;
use Mason::Plugin::PSGIHandler::PlackResponse;
use Method::Signatures::Simple;
use Moose::Role;
use namespace::autoclean;

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

around 'construct_page_component' => sub {
    my $orig = shift;
    my $self = shift;
    my ( $compc, $args ) = @_;

    use d;

    if ( blessed($args) && $args->can('get_all') ) {
        my $orig_args = $args;
        $args = $orig_args->as_hashref;

        # TODO: cache this
        my @array_attrs =
          map { $_->name }
          grep { $_->has_type_constraint && $_->type_constraint->is_a_type_of('ArrayRef') }
          $compc->meta->get_all_attributes;
        foreach my $attr (@array_attrs) {
            $args->{$attr} = [ $orig_args->get_all($attr) ];
        }
    }

    $self->$orig( $compc, $args );
};

before 'abort' => sub {
    my ( $self, $retval ) = @_;
    $self->res->status($retval) if defined($retval);
};

method redirect () {
    $self->res->redirect(@_);
    $self->clear_and_abort();
}

1;
