package Mason::t::MasonCLI;
use Test::Class::Most parent => 'Mason::Test::Class';
use IPC::System::Simple qw(run);
use Mason::Util qw(trim write_file);
use Capture::Tiny qw(capture);

sub test_cli : Test(1) {
    my $self = shift;

    my $mason = "perl -Ilib bin/mason";

    my $content = '
2 + 2 = <% 2 + 2 %>
root = <% $m->interp->comp_root->[0] %>
';

    my $dir  = $self->temp_dir;
    my $file = "$dir/test.m";
    write_file( $file, $content );

    my ( $out, $err ) = capture { run("$mason $dir/test") };
    die $err if $err;
    is( trim($out), "2 + 2 = 4\nroot = $dir" );
}

1;
