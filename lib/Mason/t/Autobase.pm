package Mason::t::Autobase;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_autobase : Test(8) {
    my $self   = shift;
    my $interp = $self->interp;

    my $check_parent = sub {
        my ( $path, $parent ) = @_;

        my $base_comp_class = $interp->load($path)
          or die "could not load '$path'";
        my $parent_comp_class = ( $parent =~ /\// ) ? $interp->load($parent) : $parent;
        cmp_deeply( [ $base_comp_class->meta->superclasses ],
            [$parent_comp_class], "parent of $path is $parent" );
    };

    my $add = sub {
        my ( $path, $extends ) = @_;

        $self->add_comp(
            path => $path,
            src  => ( $extends ? "<%flags>\nextends => $extends\n</%flags>" : " " )
        );
    };

    my $remove = sub {
        my ($path) = @_;

        $self->remove_comp( path => $path, );
    };

    # Add components with no autobases, make sure they inherit from
    # Mason::Component
    #
    $add->('/comp.m');
    $add->('/foo/comp.m');
    $add->('/foo/bar/comp.m');
    $add->('/foo/bar/baz/comp.m');

    $check_parent->( '/comp.m',             'Mason::Component' );
    $check_parent->( '/foo/comp.m',         'Mason::Component' );
    $check_parent->( '/foo/bar/comp.m',     'Mason::Component' );
    $check_parent->( '/foo/bar/baz/comp.m', 'Mason::Component' );

    # Add autobases, test the parents of the components and autobases
    #
    $add->('/Base.m');
    $add->('/foo/Base.m');
    $add->('/foo/bar/baz/Base.m');
    $self->interp->flush_load_cache();

    $check_parent->( '/Base.m',             'Mason::Component' );
    $check_parent->( '/foo/Base.m',         '/Base.m' );
    $check_parent->( '/foo/bar/baz/Base.m', '/foo/Base.m' );
    $check_parent->( '/comp.m',             '/Base.m' );
    return;
    $check_parent->( '/foo/comp.m',         '/foo/Base.m' );
    $check_parent->( '/foo/bar/comp.m',     '/foo/Base.m' );
    $check_parent->( '/foo/bar/baz/comp.m', '/foo/bar/baz/Base.m' );

    $add->( '/foo/bar/baz/none.m', "undef" );
    $check_parent->( '/foo/bar/baz/none.m', 'Mason::Component' );

    $add->( '/foo/bar/baz/top.m', "'/Base.m'" );
    $check_parent->( '/foo/bar/baz/top.m', '/Base.m' );

    $add->( '/foo/bar/baz/top2.m', "'../../Base.m'" );
    $check_parent->( '/foo/bar/baz/top2.m', '/foo/Base.m' );

    # Multiple autobases same directory
    $add->('/Base.pm');
    $add->('/foo/Base.pm');
    $self->interp->flush_load_cache();
    $check_parent->( '/Base.pm',     'Mason::Component' );
    $check_parent->( '/Base.m',      '/Base.pm' );
    $check_parent->( '/foo/Base.pm', '/Base.m' );
    $check_parent->( '/foo/Base.m',  '/foo/Base.pm' );
    $check_parent->( '/foo/comp.m',  '/foo/Base.m' );

    # Remove most autobases, test parents again
    #
    $remove->('/Base.pm');
    $remove->('/Base.m');
    $remove->('/foo/Base.pm');
    $remove->('/foo/Base.m');
    $self->interp->flush_load_cache();

    $check_parent->( '/comp.m',             'Mason::Component' );
    $check_parent->( '/foo/comp.m',         'Mason::Component' );
    $check_parent->( '/foo/bar/comp.m',     'Mason::Component' );
    $check_parent->( '/foo/bar/baz/comp.m', '/foo/bar/baz/Base.m' );
    $check_parent->( '/foo/bar/baz/Base.m', 'Mason::Component' );

}

sub test_wrapping : Tests(2) {
    my $self = shift;

    $self->add_comp(
        path => '/wrap/Base.m',
        src  => '
<%augment wrap>
<html>
% inner();
</html>
</%augment>
'
    );
    $self->add_comp(
        path => '/wrap/subdir/Base.m',
        src  => '

<%method hello>
Hello world
</%method>

'
    );
    $self->add_comp(
        path => '/wrap/subdir/subdir2/Base.m',
        src  => '
<%augment wrap>
<body>
% inner();
</body>
</%augment>
'
    );
    $self->test_comp(
        path   => '/wrap/subdir/subdir2/wrap_me.m',
        src    => '<% $self->hello %>',
        expect => '
<html>

<body>

Hello world
</body>
</html>
'
    );
    $self->test_comp(
        path => '/wrap/subdir/subdir2/dont_wrap_me.m',
        src  => '
%% method wrap { $.main() }
<% $self->hello() %>
',
        expect => 'Hello world'
    );
}

# not yet implemented
sub _test_no_main_in_autobase {
    my $self = shift;

    $self->test_comp(
        path => '/wrap/Base.m',
        src  => '
<body>
% inner();
</body>
',
        expect_error => qr/content found in main body of autobase/,
    );
}

sub test_recompute_inherit : Test(1) {
    my $self   = shift;
    my $interp = $self->interp;

    # Test that /comp.m class can be recomputed without garbage collection issues.
    #
    my $remove = sub {
        my ($path) = @_;

        $self->remove_comp( path => $path, );
    };

    $self->add_comp( path => '/comp.m', src => ' ' );
    $self->interp->load('/comp.m');
    $self->add_comp( path => '/Base.m', src => ' ' );
    $self->interp->flush_load_cache();
    $self->interp->load('/comp.m');
    ok(1);

    return;
}

1;
