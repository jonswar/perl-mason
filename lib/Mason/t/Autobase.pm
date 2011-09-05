package Mason::t::Autobase;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_autobase : Tests {
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
    $add->('/comp.mc');
    $add->('/foo/comp.mc');
    $add->('/foo/bar/comp.mc');
    $add->('/foo/bar/baz/comp.mc');

    my $base_class = $self->interp->component_class;

    $check_parent->( '/comp.mc',             $base_class );
    $check_parent->( '/foo/comp.mc',         $base_class );
    $check_parent->( '/foo/bar/comp.mc',     $base_class );
    $check_parent->( '/foo/bar/baz/comp.mc', $base_class );

    # Add autobases, test the parents of the components and autobases
    #
    $add->('/Base.mc');
    $add->('/foo/Base.mc');
    $add->('/foo/bar/baz/Base.mc');
    $self->interp->_flush_load_cache();

    $check_parent->( '/Base.mc',             $base_class );
    $check_parent->( '/foo/Base.mc',         '/Base.mc' );
    $check_parent->( '/foo/bar/baz/Base.mc', '/foo/Base.mc' );
    $check_parent->( '/comp.mc',             '/Base.mc' );

    $check_parent->( '/foo/comp.mc',         '/foo/Base.mc' );
    $check_parent->( '/foo/bar/comp.mc',     '/foo/Base.mc' );
    $check_parent->( '/foo/bar/baz/comp.mc', '/foo/bar/baz/Base.mc' );

    $add->( '/foo/bar/baz/none.mc', "undef" );
    $check_parent->( '/foo/bar/baz/none.mc', $base_class );

    $add->( '/foo/bar/baz/top.mc', "'/Base.mc'" );
    $check_parent->( '/foo/bar/baz/top.mc', '/Base.mc' );

    $add->( '/foo/bar/baz/top2.mc', "'../../Base.mc'" );
    $check_parent->( '/foo/bar/baz/top2.mc', '/foo/Base.mc' );

    # Multiple autobases same directory
    $add->('/Base.mp');
    $add->('/foo/Base.mp');
    $self->interp->_flush_load_cache();
    $check_parent->( '/Base.mp',     $base_class );
    $check_parent->( '/Base.mc',     '/Base.mp' );
    $check_parent->( '/foo/Base.mp', '/Base.mc' );
    $check_parent->( '/foo/Base.mc', '/foo/Base.mp' );
    $check_parent->( '/foo/comp.mc', '/foo/Base.mc' );

    # Remove most autobases, test parents again
    #
    $remove->('/Base.mp');
    $remove->('/Base.mc');
    $remove->('/foo/Base.mp');
    $remove->('/foo/Base.mc');
    $self->interp->_flush_load_cache();

    $check_parent->( '/comp.mc',             $base_class );
    $check_parent->( '/foo/comp.mc',         $base_class );
    $check_parent->( '/foo/bar/comp.mc',     $base_class );
    $check_parent->( '/foo/bar/baz/comp.mc', '/foo/bar/baz/Base.mc' );
    $check_parent->( '/foo/bar/baz/Base.mc', $base_class );
}

sub test_cycles : Tests {
    my $self = shift;

    # An inheritance cycle
    #
    $self->add_comp(
        path => '/cycle/Base.mc',
        src  => "<%flags>\nextends => '/cycle/c/index.mc'\n</%flags>\n",
    );
    $self->test_comp(
        path         => '/cycle/c/index.mc',
        src          => "ok",
        expect_error => qr/inheritance cycle/,
    );

    # This isn't a cycle but a bug that tried to preload default parent was causing
    # it to infinite loop
    #
    $self->add_comp(
        path => '/pseudo/Base.mc',
        src  => "<%flags>\nextends => '/pseudo/c/index.mc'\n</%flags>\n",
    );
    $self->test_comp(
        path   => '/pseudo/c/index.mc',
        src    => "<%flags>\nextends => undef\n</%flags>\nok",
        expect => 'ok',
    );
}

sub test_wrapping : Tests {
    my $self = shift;

    $self->add_comp(
        path => '/wrap/Base.mc',
        src  => '
<%augment wrap>
<html>
% inner();
</html>
</%augment>
'
    );
    $self->add_comp(
        path => '/wrap/subdir/Base.mc',
        src  => '

<%method hello>
Hello world
</%method>

'
    );
    $self->add_comp(
        path => '/wrap/subdir/subdir2/Base.mc',
        src  => '
<%augment wrap>
<body>
% inner();
</body>
</%augment>
'
    );
    $self->test_comp(
        path   => '/wrap/subdir/subdir2/wrap_me.mc',
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
        path => '/wrap/subdir/subdir2/dont_wrap_me.mc',
        src  => '
<%class>method wrap { $.main() }</%class>
<% $self->hello() %>
',
        expect => 'Hello world'
    );
    $self->test_comp(
        path => '/wrap/subdir/subdir2/dont_wrap_me_either.mc',
        src  => '
<%class>CLASS->no_wrap;</%class>
<% $self->hello() %>
',
        expect => 'Hello world'
    );
}

# not yet implemented
sub _test_no_main_in_autobase {
    my $self = shift;

    $self->test_comp(
        path => '/wrap/Base.mc',
        src  => '
<body>
% inner();
</body>
',
        expect_error => qr/content found in main body of autobase/,
    );
}

sub test_recompute_inherit : Tests {
    my $self   = shift;
    my $interp = $self->interp;

    # Test that /comp.mc class can be recomputed without garbage collection issues.
    #
    my $remove = sub {
        my ($path) = @_;

        $self->remove_comp( path => $path, );
    };

    $self->add_comp( path => '/comp.mc', src => ' ' );
    $self->interp->load('/comp.mc');
    $self->add_comp( path => '/Base.mc', src => ' ' );
    $self->interp->_flush_load_cache();
    $self->interp->load('/comp.mc');
    ok(1);

    return;
}

1;
