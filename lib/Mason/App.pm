package Mason::App;
use Cwd qw(realpath);
use File::Basename;
use File::Temp qw(tempdir);
use Getopt::Long;
use Mason;
use JSON;
use strict;
use warnings;

my $usage =
  "usage: $0 [--data-dir dir] [--plugins Plugin1,Plugin2] [--args json-string] [-e source] [template-file]";

sub run {
    my ( %params, $args, $source, $help );
    GetOptions(
        'args=s' => \$args,
        'e=s'    => \$source,
        'h|help' => \$help,
        map { dashify($_) . "=s" => \$params{$_} } qw(data_dir plugins)
    ) or usage();
    if ($help) {
        system("perldoc $0");
        exit;
    }
    %params = map { defined( $params{$_} ) ? ( $_, $params{$_} ) : () } keys(%params);
    if ( $params{plugins} ) {
        $params{plugins} = [ split( /\s*,\s*/, $params{plugins} ) ];
    }
    my %run_args = defined($args) ? %{ decode_json($args) } : ();

    my $tempdir = tempdir( 'mason-XXXX', TMPDIR => 1, CLEANUP => 1 );
    my $file;
    if ($source) {
        $file = "$tempdir/source.m";
        open( my $fh, ">", $file );
        print $fh $source;
    }
    else {
        $file = shift(@ARGV);
        usage() if @ARGV;
        if ( !$file ) {
            $file = "$tempdir/stdin.m";
            open( my $fh, ">", $file );
            while (<STDIN>) { print $fh $_ }
        }
    }

    my $comp_root = dirname($file);
    my $path      = "/" . basename($file);
    my $interp    = Mason->new( comp_root => $comp_root, autoextend_request_path => [], %params );
    print $interp->run( $path, %run_args )->output . "\n";
}

sub usage {
    print "$usage\n";
    exit;
}

sub dashify {
    my $name = shift;
    $name =~ s/_/-/g;
    return $name;
}

1;

__END__

=pod

=head1 NAME

Mason::App - Implementation of bin/mason

=head1 DESCRIPTION

See documentation for bin/mason.

=cut
