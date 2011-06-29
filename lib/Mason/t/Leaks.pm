package Mason::t::Leaks;
use Devel::LeakGuard::Object qw(leakguard);
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_foo : Tests {
    leakguard {
        my $interp = Mason->new( comp_root => "comps", data_dir => "data" );
        $interp->{interp} = $interp;
    }
    on_leak => 'die';
}

1;
