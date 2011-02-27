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
            path   => '/test_plugin.m',
            src    => '<& test_plugin_support.mi &>',
            expect => 'hi'
        );
    };

    my $like = sub { my $regex = shift; like( $output, $regex, $regex ) };
    $like->(qr/starting interp run/);
    $like->(qr/starting request run - \/test_plugin/);
    $like->(qr/starting request comp - test_plugin_support.mi/);
    $like->(qr/starting compilation parse - \/test_plugin.m/);
}

sub test_strict_plugin : Tests {
    my $self = shift;

    $self->setup_interp(
        base_component_moose_class => 'Mason::Test::Overrides::Component::StrictMoose', );
    $self->add_comp( path => '/test_strict_plugin.m', src => 'hi' );
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
        my $interp = Mason->new( plugins => $plugin_list );
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

1;
