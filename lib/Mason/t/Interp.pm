package Mason::t::Interp;
use strict;
use warnings;
use File::Temp qw(tempdir);
use Test::More;
use base qw(Mason::Test::Class);

sub test_component_class_prefix : Test(6) {
    my $self = shift;

    my $check_prefix = sub {
        my $interp = shift;
        my $regex  = "^" . $interp->component_class_prefix . "::";
        like( $interp->load('/foo.m'), qr/$regex/, "prefix at beginning of path" );
    };

    $self->add_comp( path => '/foo.m', component => 'foo' );

    my @interp =
      map { Mason::Interp->new( comp_root => $self->{comp_root}, data_dir => $self->{data_dir}, ); }
      ( 0 .. 1 );
    ok( $interp[0]->component_class_prefix ne $interp[1]->component_class_prefix,
        "different prefixes" );
    ok( $interp[0]->load('/foo.m') ne $interp[1]->load('/foo.m'), "different classnames" );

    $check_prefix->( $interp[0] );
    $check_prefix->( $interp[1] );

    $interp[2] = Mason::Interp->new(
        component_class_prefix => 'Blah',
        comp_root              => $self->{comp_root},
        data_dir               => $self->{data_dir}
    );
    is( $interp[2]->component_class_prefix, 'Blah', 'specified prefix' );
    $check_prefix->( $interp[2] );
}

1;
