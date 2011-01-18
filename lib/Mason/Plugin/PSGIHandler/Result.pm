package Mason::Plugin::PSGIHandler::Result;
use Moose::Role;
use namespace::autoclean;

has 'plack_response' => (is => 'rw');

1;
