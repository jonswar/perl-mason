package Mason::t::Compilation;
use Test::Class::Most parent => 'Mason::Test::Class';

sub test_pure_perl : Tests {
    my $self = shift;

    my $std =
      sub { my $num = shift; sprintf( 'method main () { my $foo = %s; print $foo; }', $num ) };

    $self->add_comp( path => '/print1.pl', src => $std->(53) );
    $self->test_comp(
        path   => '/top1.pm',
        src    => 'method main () { $m->comp("/print1.pl") }',
        expect => $std->(53),
    );

    $self->setup_interp( pure_perl_extensions => ['.pl'] );
    $self->add_comp( path => '/print2.pl', src => $std->(54) );
    $self->test_comp( path => '/top2.pm', src => '<& print2.pl &>', expect => '54' );

    $self->setup_interp( pure_perl_extensions => [] );
    $self->add_comp( path => '/print3.pl', src => $std->(55) );
    $self->test_comp(
        path   => '/top3.pm',
        src    => '<& print3.pl &>',
        expect => $std->(55),
    );
}

1;
