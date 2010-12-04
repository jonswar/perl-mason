package Mason::t::Autohandler;
use strict;
use warnings;
use Test::Most;
use base qw(Mason::Test::Class);

sub test_autohandler : Test(20) {
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

    # Add components with no autohandlers, make sure they inherit from
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

    $add->('/autohandler.m');
    $add->('/foo/autohandler.m');
    $add->('/foo/bar/baz/autohandler.m');

    # Add autohandlers, test the parents of the components and autohandlers
    #
    $self->{interp}->flush_load_cache();
    $check_parent->( '/autohandler.m',             'Mason::Component' );
    $check_parent->( '/foo/autohandler.m',         '/autohandler.m' );
    $check_parent->( '/foo/bar/baz/autohandler.m', '/foo/autohandler.m' );
    $check_parent->( '/comp.m',                    '/autohandler.m' );
    $check_parent->( '/foo/comp.m',                '/foo/autohandler.m' );
    $check_parent->( '/foo/bar/comp.m',            '/foo/autohandler.m' );
    $check_parent->( '/foo/bar/baz/comp.m',        '/foo/bar/baz/autohandler.m' );

    $add->( '/foo/bar/baz/none.m', "undef" );
    $check_parent->( '/foo/bar/baz/none.m', 'Mason::Component' );

    $add->( '/foo/bar/baz/top.m', "'/autohandler.m'" );
    $check_parent->( '/foo/bar/baz/top.m', '/autohandler.m' );

    $add->( '/foo/bar/baz/top2.m', "'../../autohandler.m'" );
    $check_parent->( '/foo/bar/baz/top2.m', '/foo/autohandler.m' );

    $self->remove_comp( path => '/autohandler.m' );
    $self->remove_comp( path => '/foo/autohandler.m' );

    # Remove most autohandlers, test parents again
    #
    $self->{interp}->flush_load_cache();
    $check_parent->( '/comp.m',                    'Mason::Component' );
    $check_parent->( '/foo/comp.m',                'Mason::Component' );
    $check_parent->( '/foo/bar/comp.m',            'Mason::Component' );
    $check_parent->( '/foo/bar/baz/comp.m',        '/foo/bar/baz/autohandler.m' );
    $check_parent->( '/foo/bar/baz/autohandler.m', 'Mason::Component' );

}

sub test_wrapping : Tests(2) {
    my $self = shift;
    $self->add_comp(
        path      => '/wrap/autohandler.m',
        component => <<EOF,
<%method render>
<body>
% inner();
</body>
</%method>
EOF
    );
    $self->test_comp(
        path      => '/wrap/wrap_me.m',
        component => <<EOF,
Hello world
EOF
        expect => <<EOF,

<body>
Hello world
</body>
EOF
    );
    $self->test_comp(
        path      => '/wrap/dont_wrap_me.m',
        component => <<EOF,
<%class>sub render { shift->main() }</%class>
Hello world
EOF
        expect => <<EOF,
Hello world
EOF
    );
}

1;
