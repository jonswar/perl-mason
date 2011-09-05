package Mason::t::Reload;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_reload : Tests {
    my $self = shift;
    my $class;

    $self->add_comp(
        path => "/reload.mc",
        src  => <<'EOF',
<%class>
sub foo { 'foo' }
sub baz { 'baz1' }
</%class>
Foo
EOF
    );
    is( $self->interp->run("/reload")->output, "Foo\n", "before reload" );
    $class = $self->interp->load("/reload.mc");
    is( $class->foo(), 'foo',  "method foo" );
    is( $class->baz(), 'baz1', "method baz" );
    ok( $class->can('foo'),  "can call foo before reload" );
    ok( !$class->can('bar'), "cannot call bar before reload" );
    ok( $class->can('baz'),  "can call baz before reload" );

    sleep(1);    # so timestamp will be different

    $self->add_comp(
        path => "/reload.mc",
        src  => <<'EOF',
<%class>
sub bar { 'bar' }
sub baz { 'baz2' }
</%class>
Bar
EOF
    );
    is( $self->interp->run("/reload")->output, "Bar\n", "after reload" );
    is( $class->bar(),                         'bar',   "method bar" );
    is( $class->baz(),                         'baz2',  "method baz" );
    ok( $class->can('bar'),  "can call bar after reload" );
    ok( !$class->can('foo'), "cannot call foo after reload" );
    ok( $class->can('baz'),  "can call baz after reload" );
}

sub test_reload_parent : Tests {
    my $self   = shift;
    my $interp = $self->interp;

    $self->add_comp( path => '/foo/bar/baz.mc', src => '<% $.num1 %> <% $.num2 %>' );
    $self->add_comp( path => '/foo/Base.mc',    src => '<%class>method num1 { 5 }</%class>' );
    $self->add_comp( path => '/Base.mc',        src => '<%class>method num2 { 6 }</%class>' );

    $self->test_existing_comp( path => '/foo/bar/baz.mc', expect => '5 6' );

    $self->interp->_flush_load_cache();
    sleep(1);

    $self->add_comp( path => '/foo/Base.mc', src => "<%class>method num1 { 7 }</%class>" );
    $self->add_comp( path => '/Base.mc',     src => "<%class>method num2 { 8 }</%class>" );
    $self->test_existing_comp( path => '/foo/bar/baz.mc', expect => '7 8' );

    $self->interp->_flush_load_cache();
    sleep(1);

    $self->add_comp(
        path => '/Base.mc',
        src  => "<%class>method num1 { 10 }\nmethod num2 { 11 }\n</%class>"
    );
    $self->test_existing_comp( path => '/foo/bar/baz.mc', expect => '7 11' );

    $self->interp->_flush_load_cache();
    sleep(1);

    $self->remove_comp( path => '/foo/Base.mc' );
    $self->test_existing_comp( path => '/foo/bar/baz.mc', expect => '10 11' );

    $self->interp->_flush_load_cache();
    sleep(1);

    $self->remove_comp( path => '/foo/Base.mc' );
    $self->add_comp( path => '/foo/bar/baz.mc', src => 'hi' );
    $self->add_comp( path => '/Base.mp',        src => 'method wrap { print "wrap1" }' );
    $self->test_existing_comp( path => '/foo/bar/baz.mc', expect => 'wrap1' );

    $self->interp->_flush_load_cache();
    sleep(1);

    $self->add_comp( path => '/Base.mp', src => 'method wrap { print "wrap2" }' );
    $self->test_existing_comp( path => '/foo/bar/baz.mc', expect => 'wrap2' );
}

sub test_no_unnecessary_reload : Tests {
    my $self   = shift;
    my $interp = $self->interp;

    $self->add_comp( path => '/foo.mc', src => ' ' );
    my $id1 = $interp->load('/foo.mc')->cmeta->id;
    $self->interp->_flush_load_cache();
    my $id2 = $interp->load('/foo.mc')->cmeta->id;
    ok( $id1 == $id2 );
}

1;
