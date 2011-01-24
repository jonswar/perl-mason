#!/usr/bin/perl
use lib qw(/Users/swartz/git/mason.git/lib);
use Cwd qw(realpath);
use File::Basename;
use Mason;
use YAML qw(LoadFile);
use warnings;
use strict;

# Directory of this script
my $cwd = dirname( realpath(__FILE__) );

# Load constructor params from mason.yml
my $params = LoadFile("$cwd/mason.yml");

# Create Mason object
my $interp = Mason->new(
    comp_root => "$cwd/comps",
    data_dir  => "$cwd/data",
    %$params
);

# Return PSGI handler
my $handler = sub {
    my $env = shift;
    $interp->handle_psgi($env);
};
