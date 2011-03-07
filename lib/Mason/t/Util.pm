package Mason::t::Util;
use Test::Class::Most parent => 'Mason::Test::Class';
use Mason::Util qw(combine_similar_paths);

sub test_combine_similar_paths : Tests {
    cmp_deeply( [ combine_similar_paths(qw(/foo/bar.m /foo/bar.pm /foo.m /foo.pm)) ],
        [ '/foo/bar.{m,pm}', '/foo.{m,pm}' ] );
}

1;
