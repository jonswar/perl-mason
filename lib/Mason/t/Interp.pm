package Mason::t::Interp;
use strict;
use warnings;
use File::Temp qw(tempdir);
use Test::Most;
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
      map { $self->create_interp() } ( 0 .. 1 );
    ok( $interp[0]->component_class_prefix ne $interp[1]->component_class_prefix,
        "different prefixes" );
    ok( $interp[0]->load('/foo.m') ne $interp[1]->load('/foo.m'), "different classnames" );

    $check_prefix->( $interp[0] );
    $check_prefix->( $interp[1] );

    $interp[2] = $self->create_interp( component_class_prefix => 'Blah' );
    is( $interp[2]->component_class_prefix, 'Blah', 'specified prefix' );
    $check_prefix->( $interp[2] );
}

sub test_bad_param : Test(1) {
    my $self = shift;
    throws_ok { $self->create_interp( foo => 5 ) } qr/Found unknown attribute/;
}

sub test_comp_exists : Test(3) {
    my $self = shift;

    $self->add_comp( path => '/comp_exists/one.m', component => 'hi' );
    my $interp = $self->{interp};
    ok( $interp->comp_exists('/comp_exists/one.m') );
    ok( !$interp->comp_exists('/comp_exists/two.m') );
    throws_ok { $interp->comp_exists('one.m') } qr/not an absolute/;
}

1;
