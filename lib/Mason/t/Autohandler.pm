package Mason::t::Autohandler;
use strict;
use warnings;
use Test::Most;
use base qw(Mason::Test::Class);

sub test_autohandler : Test(16) {
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
        my ($path) = @_;

        $self->add_comp( path => $path, component => ' ' );
    };

    # Add components with no autohandlers, make sure they inherit from
    # Mason::Component
    #
    $add->('/comp');
    $add->('/foo/comp');
    $add->('/foo/bar/comp');
    $add->('/foo/bar/baz/comp');

    $check_parent->( '/comp',             'Mason::Component' );
    $check_parent->( '/foo/comp',         'Mason::Component' );
    $check_parent->( '/foo/bar/comp',     'Mason::Component' );
    $check_parent->( '/foo/bar/baz/comp', 'Mason::Component' );

    $add->('/autohandler');
    $add->('/foo/autohandler');
    $add->('/foo/bar/baz/autohandler');

    # Add autohandlers, test the parents of the components and autohandlers
    #
    $self->{interp}->flush_load_cache();
    $check_parent->( '/autohandler',             'Mason::Component' );
    $check_parent->( '/foo/autohandler',         '/autohandler' );
    $check_parent->( '/foo/bar/baz/autohandler', '/foo/autohandler' );
    $check_parent->( '/comp',                    '/autohandler' );
    $check_parent->( '/foo/comp',                '/foo/autohandler' );
    $check_parent->( '/foo/bar/comp',            '/foo/autohandler' );
    $check_parent->( '/foo/bar/baz/comp',        '/foo/bar/baz/autohandler' );

    $self->remove_comp( path => '/autohandler' );
    $self->remove_comp( path => '/foo/autohandler' );

    # Remove most autohandlers, test parents again
    #
    $self->{interp}->flush_load_cache();
    $check_parent->( '/comp',                    'Mason::Component' );
    $check_parent->( '/foo/comp',                'Mason::Component' );
    $check_parent->( '/foo/bar/comp',            'Mason::Component' );
    $check_parent->( '/foo/bar/baz/comp',        '/foo/bar/baz/autohandler' );
    $check_parent->( '/foo/bar/baz/autohandler', 'Mason::Component' );
}

sub test_wrapping : Tests(2) {
    my $self = shift;
    $self->add_comp(
        path      => '/wrap/autohandler',
        component => <<EOF,
<%method render>
<body>
% inner();
</body>
</%method>
EOF
    );
    $self->test_comp(
        path      => '/wrap/wrap_me',
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
        path      => '/wrap/dont_wrap_me',
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
