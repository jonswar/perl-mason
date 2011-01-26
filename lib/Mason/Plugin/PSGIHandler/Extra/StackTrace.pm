package Mason::Plugin::PSGIHandler::Extra::StackTrace;
use strict;
use warnings;
use base qw(Devel::StackTrace);

sub new {
    my $class = shift;
    $class->SUPER::new( @_, frame_filter => \&_frame_filter );
}

sub _frame_filter {
    my $info = shift;
    my ( $pkg, $file, $line, $method ) = @{ $info->{caller} };
    return $pkg !~ /^(Moose|Mason|Class::MOP)/;
}

1;
