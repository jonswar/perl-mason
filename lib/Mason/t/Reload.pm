package Mason::t::Reload;
use strict;
use warnings;
use Test::More;
use base qw(Mason::Test::Class);

sub test_reload : Test(12) {
    my $self = shift;
    my $class;

    $self->add_comp(
        path      => "/reload",
        component => <<'EOF',
<%class>
sub foo { 'foo' }
sub baz { 'baz1' }
</%class>
Foo
EOF
    );
    is( $self->{interp}->srun("/reload"), "Foo\n", "before reload" );
    $class = $self->{interp}->load("/reload");
    is( $class->foo(), 'foo',  "method foo" );
    is( $class->baz(), 'baz1', "method baz" );
    ok( $class->can('foo'),  "can call foo before reload" );
    ok( !$class->can('bar'), "cannot call bar before reload" );
    ok( $class->can('baz'),  "can call baz before reload" );

    sleep(1);    # so timestamp will be different

    $self->add_comp(
        path      => "/reload",
        component => <<'EOF',
<%class>
sub bar { 'bar' }
sub baz { 'baz2' }
</%class>
Bar
EOF
    );
    is( $self->{interp}->srun("/reload"), "Bar\n", "after reload" );
    is( $class->bar(),                    'bar',   "method bar" );
    is( $class->baz(),                    'baz2',  "method baz" );
    ok( $class->can('bar'),  "can call bar after reload" );
    ok( !$class->can('foo'), "cannot call foo after reload" );
    ok( $class->can('baz'),  "can call baz after reload" );
}

1;
