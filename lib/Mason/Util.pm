package Mason::Util;
use Carp;
use Class::MOP;
use Class::Unload;
use Data::UUID;
use Fcntl qw( :DEFAULT :seek );
use File::Spec::Functions ();
use Try::Tiny;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK =
  qw(can_load catdir catfile checksum dump_one_line mason_canon_path read_file touch_file trim unique_id write_file);

my $Fetch_Flags          = O_RDONLY | O_BINARY;
my $Store_Flags          = O_WRONLY | O_CREAT | O_BINARY;
my $File_Spec_Using_Unix = $File::Spec::ISA[0] eq 'File::Spec::Unix';

sub can_load {

    # Load $class_name if possible. Return 1 if successful, 0 if it could not be
    # found, and rethrow load error (other than not found).
    #
    my ($class_name) = @_;

    my $result;
    try {
        Class::MOP::load_class($class_name);
        $result = 1;
    }
    catch {
        if ( /Can\'t locate .* in \@INC/ && !/Compilation failed/ ) {
            $result = 0;
        }
        else {
            die $_;
        }
    };
    return $result;
}

sub catdir {
    return $File_Spec_Using_Unix ? join( "/", @_ ) : File::Spec::Functions::catdir(@_);
}

sub catfile {
    return $File_Spec_Using_Unix ? join( "/", @_ ) : File::Spec::Functions::catfile(@_);
}

sub checksum {
    my ($str) = @_;

    # Adler32 algorithm
    my $s1 = 1;
    my $s2 = 1;
    for my $c ( unpack( "C*", $str ) ) {
        $s1 = ( $s1 + $c ) % 65521;
        $s2 = ( $s2 + $s1 ) % 65521;
    }
    return ( $s2 << 16 ) + $s1;
}

sub delete_package {
    my $pkg = shift;
    Class::Unload->unload($pkg);
}

sub dump_one_line {
    my ($value) = @_;

    return Data::Dumper->new( [$value] )->Indent(0)->Sortkeys(1)->Quotekeys(0)->Terse(1)->Dump();
}

sub mason_canon_path {

    # Like File::Spec::canonpath but with a few fixes.
    #
    my $path = shift;
    $path =~ s|/+|/|g;           # xx////yy  -> xx/yy
    $path =~ s|(?:/\.)+/|/|g;    # xx/././yy -> xx/yy
    {
        $path =~ s|^(?:\./)+||s unless $path eq "./";    # ./xx      -> xx
        $path =~ s|^/(?:\.\./)+|/|s;                     # /../../xx -> xx
        $path =~ s|/\Z(?!\n)|| unless $path eq "/";      # xx/       -> xx
        $path =~ s|/[^/]+/\.\.$|| && redo;               # /xx/..    -> /
        $path =~ s|[^/]+/\.\./||  && redo;               # /xx/../yy -> /yy
    }
    return $path;
}

sub read_file {
    my ($file) = @_;

    # Fast slurp, adapted from File::Slurp::read, with unnecessary options removed
    #
    my $buf = "";
    my $read_fh;
    unless ( sysopen( $read_fh, $file, $Fetch_Flags ) ) {
        croak "read_file '$file' - sysopen: $!";
    }
    my $size_left = -s $read_fh;
    while (1) {
        my $read_cnt = sysread( $read_fh, $buf, $size_left, length $buf );
        if ( defined $read_cnt ) {
            last if $read_cnt == 0;
            $size_left -= $read_cnt;
            last if $size_left <= 0;
        }
        else {
            croak "read_file '$file' - sysread: $!";
        }
    }
    return $buf;
}

sub touch_file {
    my ($file) = @_;
    if ( -f $file ) {
        my $time = time;
        utime( $time, $time, $file );
    }
    else {
        write_file( $file, "" );
    }
}

sub trim {
    my ($str) = @_;
    if ( defined($str) ) {
        for ($str) { s/^\s+//; s/\s+$// }
    }
    return $str;
}

{

    # For efficiency, use Data::UUID to generate an initial unique id, then suffix it to
    # generate a series of 0x10000 unique ids. Not to be used for hard-to-guess ids, obviously.

    my $uuid;
    my $suffix = 0;

    sub unique_id {
        if ( !$suffix || !defined($uuid) ) {
            my $ug = Data::UUID->new();
            $uuid = $ug->create_hex();
        }
        my $hex = sprintf( '%s%04x', $uuid, $suffix );
        $suffix = ( $suffix + 1 ) & 0xffff;
        return $hex;
    }
}

sub write_file {
    my ( $file, $data, $file_create_mode ) = @_;
    $file_create_mode = oct(666) if !defined($file_create_mode);

    # Fast spew, adapted from File::Slurp::write, with unnecessary options removed
    #
    {
        my $write_fh;
        unless ( sysopen( $write_fh, $file, $Store_Flags, $file_create_mode ) ) {
            croak "write_file '$file' - sysopen: $!";
        }
        my $size_left = length($data);
        my $offset    = 0;
        do {
            my $write_cnt = syswrite( $write_fh, $data, $size_left, $offset );
            unless ( defined $write_cnt ) {
                croak "write_file '$file' - syswrite: $!";
            }
            $size_left -= $write_cnt;
            $offset += $write_cnt;
        } while ( $size_left > 0 );
        truncate( $write_fh, sysseek( $write_fh, 0, SEEK_CUR ) )
    }
}

1;
