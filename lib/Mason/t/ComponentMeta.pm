package Mason::t::ComponentMeta;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_cmeta : Tests {
    my $self = shift;
    $self->run_test_in_comp(
        path => '/component/meta.mc',
        args => { foo => 5, bar => [ 'baz', 7 ] },
        test => sub {
            my $comp        = shift;
            my $source_file = $self->comp_root . '/component/meta.mc';
            foreach my $cmeta ( $comp->cmeta, ref($comp)->cmeta ) {
                is( $cmeta->path,         '/component/meta.mc', 'path' );
                is( $cmeta->dir_path,     '/component',         'dir_path' );
                is( $cmeta->is_top_level, 1,                    'is_top_level' );
                is( $cmeta->source_file,  $source_file,         'source_file' );
                like( $cmeta->object_file, qr|/component/meta.mc.mobj|, 'object_file' );
            }
            my $args = $comp->args;
            delete( $args->{_test} );
            cmp_deeply( $args, { foo => 5, bar => [ 'baz', 7 ] } );
        },
    );
}

1;
