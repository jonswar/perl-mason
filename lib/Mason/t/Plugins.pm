package Mason::t::Plugins;
use Test::Class::Most parent => 'Mason::Test::Class';
use Capture::Tiny qw(capture_merged);
use Mason::Util qw(dump_one_line);

sub test_notify_plugin : Tests {
    my $self = shift;

    $self->setup_interp(
        plugins                => ['+Mason::Test::Plugins::Notify'],
        no_source_line_numbers => 1,
    );
    $self->add_comp( path => '/test_plugin_support.mi', src => 'hi' );
    my $output = capture_merged {
        $self->test_comp(
            path   => '/test_plugin.mc',
            src    => '<& test_plugin_support.mi &>',
            expect => 'hi'
        );
    };

    my $like = sub { my $regex = shift; like( $output, $regex, $regex ) };
    $like->(qr/starting interp run/);
    $like->(qr/starting request run - \/test_plugin/);
    $like->(qr/starting request comp - test_plugin_support.mi/);
    $like->(qr/starting compilation parse - \/test_plugin.mc/);
}

# Call Mason::Test::RootClass->new, then make base classes like
# Mason::Test::RootClass::Interp are used automatically
#
sub test_notify_root_class : Tests {
    my $self = shift;
    my $mrc  = 'Mason::Test::RootClass';
    $self->setup_interp( mason_root_class => $mrc );
    is( $self->interp->mason_root_class,       $mrc,                  "mason_root_class" );
    is( $self->interp->base_compilation_class, "${mrc}::Compilation", "base_compilation_class" );
    is( $self->interp->base_component_class,   "${mrc}::Component",   "base_component_class" );
    is( $self->interp->base_request_class,     "${mrc}::Request",     "base_request_class" );
    is( $self->interp->base_result_class,      "Mason::Result",       "base_result_class" );
    isa_ok( $self->interp, "${mrc}::Interp", "base_interp_class" );

    $self->add_comp( path => '/test_plugin_support.mi', src => 'hi' );
    my $output = capture_merged {
        $self->test_comp(
            path   => '/test_plugin.mc',
            src    => '<& test_plugin_support.mi &>',
            expect => 'hi'
        );
    };

    my $like = sub { my $regex = shift; like( $output, $regex, $regex ) };
    $like->(qr/starting interp run/);
    $like->(qr/starting request run - \/test_plugin/);
    $like->(qr/starting request comp - test_plugin_support.mi/);
    $like->(qr/starting compilation parse - \/test_plugin.mc/);
}

sub test_strict_plugin : Tests {
    my $self = shift;

    $self->setup_interp(
        base_component_moose_class => 'Mason::Test::Overrides::Component::StrictMoose', );
    $self->add_comp( path => '/test_strict_plugin.mc', src => 'hi' );
    lives_ok { $self->interp->run('/test_strict_plugin') };
    throws_ok { $self->interp->run( '/test_strict_plugin', foo => 5 ) } qr/Found unknown attribute/;
}

{ package Mason::Test::Plugins::A; use Moose; with 'Mason::Plugin'; }
{ package Mason::Plugin::B;        use Moose; with 'Mason::Plugin'; }
{ package Mason::Plugin::C;        use Moose; with 'Mason::Plugin'; }
{ package Mason::Plugin::D;        use Moose; with 'Mason::Plugin'; }
{ package Mason::Plugin::E;        use Moose; with 'Mason::Plugin'; }
{
    package Mason::PluginBundle::F;
    use Moose;
    with 'Mason::PluginBundle';
    sub requires_plugins { return qw(C D) }
}
{
    package Mason::Test::PluginBundle::G;
    use Moose;
    with 'Mason::PluginBundle';
    sub requires_plugins { return qw(C E) }
}
{
    package Mason::Plugin::H;
    use Moose;
    with 'Mason::Plugin';
    sub requires_plugins { return qw(@F) }
}
{
    package Mason::PluginBundle::I;
    use Moose;
    with 'Mason::PluginBundle';

    sub requires_plugins {
        return ( '+Mason::Test::Plugins::A', 'B', '@F', '+Mason::Test::PluginBundle::G', );
    }
}

{
    package Mason::PluginBundle::J;
    use Moose;
    with 'Mason::PluginBundle';

    sub requires_plugins {
        return ('@I');
    }
}

sub test_plugin_specs : Tests {
    my $self = shift;

    require Mason::PluginBundle::Default;
    my @default_plugins = Mason::PluginBundle::Default->requires_plugins
      or die "no default plugins";
    my $test = sub {
        my ( $plugin_list, $expected_plugins ) = @_;
        my $interp = Mason->new( comp_root => $self->comp_root, plugins => $plugin_list );
        my $got_plugins =
          [ map { /Mason::Plugin::/ ? substr( $_, 15 ) : $_ } @{ $interp->plugins } ];
        cmp_deeply(
            $got_plugins,
            [ @$expected_plugins, @default_plugins ],
            dump_one_line($plugin_list)
        );
    };
    $test->( [], [] );
    $test->( ['E'], ['E'] );
    $test->( ['H'], [ 'H', 'C', 'D' ] );
    $test->( ['@F'], [ 'C', 'D' ] );
    $test->( ['@I'], [ 'Mason::Test::Plugins::A', 'B', 'C', 'D', 'E' ] );
    $test->( [ '-C', '@I', '-+Mason::Test::Plugins::A' ], [ 'B', 'D', 'E' ] );
    $test->( [ '-@I', '@J' ], [] );
    throws_ok { $test->( ['@X'] ) } qr/could not load 'Mason::PluginBundle::X'/;
    throws_ok { $test->( ['Y'] ) } qr/could not load 'Mason::Plugin::Y'/;
}

{ package Mason::Test::Plugins::Upper; use Moose; with 'Mason::Plugin' }
{
    package Mason::Test::Plugins::Upper::Request;
    use Mason::PluginRole;
    after 'process_output' => sub {
        my ( $self, $bufref ) = @_;
        $$bufref = uc($$bufref);
    };
}

sub test_process_output_plugin : Tests {
    my $self = shift;

    $self->setup_interp( plugins => ['+Mason::Test::Plugins::Upper'] );
    $self->test_comp( src => 'Hello', expect => 'HELLO' );
}

1;
