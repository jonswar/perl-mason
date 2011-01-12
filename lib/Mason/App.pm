package Mason::App;
use Cwd qw(realpath);
use File::Basename;
use File::Temp qw(tempdir);
use Mason;
use strict;
use warnings;

sub run {
    my $file = shift(@ARGV);
    if ( !$file ) {
        my $tempdir = tempdir( 'mason-XXXX', TMPDIR => 1, CLEANUP => 1 );
        $file = "$tempdir/stdin.m";
        open( my $fh, ">", $file );
        while (<STDIN>) { print $fh $_ }
    }
    usage() if @ARGV;

    my $comp_root = dirname($file);
    my $path      = "/" . basename($file);
    my $interp    = Mason->new( comp_root => $comp_root );
    print $interp->run($path)->output . "\n";
}

1;

# ABSTRACT: Implementation of bin/mason
__END__

=head1 DESCRIPTION

See documentation for bin/mason.

=cut
