package Mason::Types;
use Moose::Util::TypeConstraints;
use strict;
use warnings;

subtype 'Mason::Types::CompRoot' => as 'ArrayRef[Str]';
coerce 'Mason::Types::CompRoot' => from 'Str' => via { [$_] };

subtype 'Mason::Types::OutMethod' => as 'CodeRef';
coerce 'Mason::Types::OutMethod' => from 'ScalarRef' => via {
    my $ref = $_;
    sub { $$ref .= $_[0] }
};

1;
