package Mason::t::Plugins;
use Test::Class::Most parent => 'Mason::Test::Class';
use Capture::Tiny qw(capture_merged);

sub test_plugins : Test(6) {
    my $self = shift;

    $self->setup_interp(
        plugins                => ['+Mason::Test::Plugins::Notify'],
        no_source_line_numbers => 1,                                   # test a compiler param
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
    $like->(qr/starting compiler compile - \/test_plugin.m/);
    $like->(qr/starting compilation compile - \/test_plugin.m/);
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

sub test_bundles : Test(6) {
    my $self = shift;

    my $test = sub {
        my ( $plugin_list, $expected_plugins ) = @_;
        my $interp = Mason->new( plugins => $plugin_list );
        my $got_plugins =
          [ map { /Mason::Plugin::/ ? substr( $_, 15 ) : $_ } @{ $interp->plugins } ];
        cmp_deeply( $got_plugins, $expected_plugins );
    };
    $test->( ['E'], ['E'] );
    $test->( ['H'], [ 'H', 'C', 'D' ] );
    $test->( ['@F'], [ 'C', 'D' ] );
    $test->( ['@I'], [ 'Mason::Test::Plugins::A', 'B', 'C', 'D', 'E' ] );
    throws_ok { $test->( ['@X'] ) } qr/could not load 'Mason::PluginBundle::X'/;
    throws_ok { $test->( ['Y'] ) } qr/could not load 'Mason::Plugin::Y'/;
}

1;
