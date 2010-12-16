package Mason::t::Autobase;
use strict;
use warnings;
use Test::Most;
use base qw(Mason::Test::Class);

sub test_autobase : Test(19) {
    my $self   = shift;
    my $interp = $self->{interp};

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
            path      => $path,
            component => ( $extends ? "<%flags>\nextends => $extends\n</%flags>" : " " )
        );
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

    $add->('/Base.m');
    $add->('/foo/Base.m');
    $add->('/foo/bar/baz/Base.m');

    # Add autobases, test the parents of the components and autobases
    #
    $self->{interp}->flush_load_cache();
    $check_parent->( '/Base.m',             'Mason::Component' );
    $check_parent->( '/foo/Base.m',         '/Base.m' );
    $check_parent->( '/foo/bar/baz/Base.m', '/foo/Base.m' );
    $check_parent->( '/comp.m',             '/Base.m' );
    $check_parent->( '/foo/comp.m',         '/foo/Base.m' );
    $check_parent->( '/foo/bar/comp.m',     '/foo/Base.m' );
    $check_parent->( '/foo/bar/baz/comp.m', '/foo/bar/baz/Base.m' );

    $add->( '/foo/bar/baz/none.m', "undef" );
    $check_parent->( '/foo/bar/baz/none.m', 'Mason::Component' );

    $add->( '/foo/bar/baz/top.m', "'/Base.m'" );
    $check_parent->( '/foo/bar/baz/top.m', '/Base.m' );

    $add->( '/foo/bar/baz/top2.m', "'../../Base.m'" );
    $check_parent->( '/foo/bar/baz/top2.m', '/foo/Base.m' );

    $self->remove_comp( path => '/Base.m' );
    $self->remove_comp( path => '/foo/Base.m' );

    # Remove most autobases, test parents again
    #
    $self->{interp}->flush_load_cache();
    $check_parent->( '/comp.m',             'Mason::Component' );
    $check_parent->( '/foo/comp.m',         'Mason::Component' );
    $check_parent->( '/foo/bar/comp.m',     'Mason::Component' );
    $check_parent->( '/foo/bar/baz/comp.m', '/foo/bar/baz/Base.m' );
    $check_parent->( '/foo/bar/baz/Base.m', 'Mason::Component' );

}

sub test_wrapping : Tests(2) {
    my $self = shift;
    $self->add_comp(
        path      => '/wrap/Base.m',
        component => '
<%wrap render>
<html>
% $m->call_next;
</html>
</%wrap>
'
    );
    $self->add_comp(
        path      => '/wrap/subdir/Base.m',
        component => '

<%method hello>
Hello world
</%method>

'
    );
    $self->add_comp(
        path      => '/wrap/subdir/subdir2/Base.m',
        component => '
<%wrap render>
<body>
% $m->call_next;
</body>
</%wrap>
'
    );
    $self->test_comp(
        path      => '/wrap/subdir/subdir2/wrap_me.m',
        component => '<% $self->hello %>',
        expect    => '
<html>

<body>

Hello world
</body>
</html>
'
    );
    $self->test_comp(
        path      => '/wrap/subdir/subdir2/dont_wrap_me.m',
        component => '
<%flags>
ignore_wrap=>1
</%flags>
<% $self->hello() %>
',
        expect => 'Hello world'
    );
}

# not yet implemented
sub _test_no_main_in_autobase {
    my $self = shift;

    $self->test_comp(
        path      => '/wrap/Base.m',
        component => '
<body>
% inner();
</body>
',
        expect_error => qr/content found in main body of autobase/,
    );
}

1;
