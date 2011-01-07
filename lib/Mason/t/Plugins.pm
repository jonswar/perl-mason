package Mason::t::Plugins;
use Test::Class::Most parent => 'Mason::Test::Class';
use Capture::Tiny qw(capture_merged);

sub test_plugins : Test(6) {
    my $self = shift;

    $self->{interp} = $self->create_interp(
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

1;
