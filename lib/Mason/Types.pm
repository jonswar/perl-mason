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

subtype 'Mason::Types::RegexpRefOrStr' => as 'RegexpRef';
coerce 'Mason::Types::RegexpRefOrStr' => from 'Str' => via { qr/$/ };

subtype 'Mason::Types::Autoextend' => as 'ArrayRef[Str]';
coerce 'Mason::Types::Autoextend' => from 'Bool' => via { $_ ? [ '.mp', '.mc' ] : [] };

1;
