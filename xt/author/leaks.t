#!perl

use strict;
use warnings;

use Devel::LeakGuard::Object qw(leakguard);
use File::Path qw(mkpath);
use File::Temp qw(tempdir);
use Test::Most;
use Mason::Util qw(write_file);
use Mason;

sub testleaks {
    my $code = shift;
    my $report;
    $code->();
    leakguard(
        sub { $code->() },
        only    => 'Mason*',
        on_leak => sub { $report = shift; }
    );
    if ($report) {
        my $desc = join("\n", map { sprintf("%s %d %d", $_, @{ $report->{$_} }) } keys(%$report));
        ok( 0, "leaks found:\n$desc" );
    }
    else {
        ok( 1, "no leaks found" );
    }
}

my $root = tempdir('name-XXXX', TMPDIR => 1, CLEANUP => 1);
my $comp_root = "$root/comps";
my $data_dir = "$root/data";
mkpath( [ $comp_root, $data_dir ], 0, 0775 );

testleaks(
    sub {
        my $interp = Mason->new( comp_root => $comp_root, data_dir => $data_dir );
        foreach my $comp (qw(foo bar)) {
            write_file("$comp_root/$comp.mc", "Hi");
            $interp->run("/$comp");
        }
    }
);

done_testing();
