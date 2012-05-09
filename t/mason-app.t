#!/usr/bin/perl
use File::Temp qw(tempdir);
use Mason::Util qw(write_file);
use Test::More tests => 3;
use warnings;
use strict;

my $tempdir = tempdir( 'mason-app-XXXX', TMPDIR => 1, CLEANUP => 1 );
my $comp_file = "$tempdir/hello.mc";
write_file( $comp_file, "%% has 'd';\nd * 2 = <% \$.d * 2 %>" );
# This string escaping may look ugly, but it is only way to make it work under
# Windows
my $output = `$^X bin/mason.pl $comp_file --data-dir $tempdir/data --args "{\\"d\\":\\"4\\"}"`;
is( $output, "d * 2 = 8\n", 'correct output' );
ok( -f "$tempdir/data/obj/hello.mc.mobj", "object file exists" );
$output = `$^X bin/mason.pl -e '<% 3+3 %>'`;
is( $output, "6\n", 'correct output' );
