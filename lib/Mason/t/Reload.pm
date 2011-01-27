package Mason::t::Reload;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_reload : Test(12) {
    my $self = shift;
    my $class;

    $self->add_comp(
        path => "/reload.m",
        src  => <<'EOF',
<%class>
sub foo { 'foo' }
sub baz { 'baz1' }
</%class>
Foo
EOF
    );
    is( $self->interp->run("/reload.m")->output, "Foo\n", "before reload" );
    $class = $self->interp->load("/reload.m");
    is( $class->foo(), 'foo',  "method foo" );
    is( $class->baz(), 'baz1', "method baz" );
    ok( $class->can('foo'),  "can call foo before reload" );
    ok( !$class->can('bar'), "cannot call bar before reload" );
    ok( $class->can('baz'),  "can call baz before reload" );

    sleep(1);    # so timestamp will be different

    $self->add_comp(
        path => "/reload.m",
        src  => <<'EOF',
<%class>
sub bar { 'bar' }
sub baz { 'baz2' }
</%class>
Bar
EOF
    );
    is( $self->interp->run("/reload.m")->output, "Bar\n", "after reload" );
    is( $class->bar(),                           'bar',   "method bar" );
    is( $class->baz(),                           'baz2',  "method baz" );
    ok( $class->can('bar'),  "can call bar after reload" );
    ok( !$class->can('foo'), "cannot call foo after reload" );
    ok( $class->can('baz'),  "can call baz after reload" );
}

sub test_reload_parent : Test(4) {
    my $self   = shift;
    my $interp = $self->interp;

    $self->add_comp( path => '/foo/bar/baz.m', src => '<% $.num1 %> <% $.num2 %>' );
    $self->add_comp( path => '/foo/Base.m',    src => '%% method num1 { 5 }' );
    $self->add_comp( path => '/Base.m',        src => '%% method num2 { 6 }' );
    $self->test_existing_comp( path => '/foo/bar/baz.m', expect => '5 6' );

    $self->interp->_flush_load_cache();
    sleep(1);

    $self->add_comp( path => '/foo/Base.m', src => "%% method num1 { 7 }" );
    $self->add_comp( path => '/Base.m',     src => "%% method num2 { 8 }" );
    $self->test_existing_comp( path => '/foo/bar/baz.m', expect => '7 8' );

    $self->interp->_flush_load_cache();
    sleep(1);

    $self->add_comp( path => '/Base.m', src => "%% method num1 { 10 } \n%% method num2 { 11 }\n" );
    $self->test_existing_comp( path => '/foo/bar/baz.m', expect => '7 11' );

    $self->interp->_flush_load_cache();
    sleep(1);

    $DB::single = 1;
    $self->remove_comp( path => '/foo/Base.m' );
    $self->test_existing_comp( path => '/foo/bar/baz.m', expect => '10 11' );
}

1;
