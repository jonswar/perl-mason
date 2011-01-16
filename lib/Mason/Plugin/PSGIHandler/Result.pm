package Mason::Plugin::PSGIHandler::Result;
use Moose::Role;

has 'plack_response' => (is => 'rw');

1;
