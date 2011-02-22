#!/usr/bin/perl
use File::Temp qw(tempdir);
use Mason::Util qw(write_file);
use Test::More tests => 2;
use warnings;
use strict;

my $tempdir = tempdir( 'mason-app-XXXX', TMPDIR => 1, CLEANUP => 1 );
my $comp_file = "$tempdir/hello.m";
write_file( $comp_file, "%% has 'd';\nd * 2 = <% \$.d * 2 %>" );
my $output = `$^X bin/mason $comp_file --data-dir $tempdir/data --args '{"d":"4"}'`;
is( $output, "d * 2 = 8\n", 'correct output' );
ok( -f "$tempdir/data/obj/hello.m.mobj", "object file exists" );
