package Mason::TieHandle;
use strict;
use warnings;

sub TIEHANDLE {
    my $class = shift;

    return bless {}, $class;
}

sub PRINT {
    my $self = shift;

    # TODO - why do we need to select STDOUT here?
    my $old = select STDOUT;
    $Mason::Request::current_request->print(@_);
    select $old;
}

sub PRINTF {
    my $self = shift;

    # apparently sprintf(@_) won't work, it needs to be a scalar
    # followed by a list
    $self->PRINT( sprintf( shift, @_ ) );
}

1;
