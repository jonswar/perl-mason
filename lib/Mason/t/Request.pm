package Mason::t::Request;
use Test::Class::Most parent => 'Mason::Test::Class';
use Log::Any::Test;
use Log::Any qw($log);

sub _get_current_comp_class {
    my $m = shift;
    return $m->current_comp_class;
}

sub test_add_cleanup : Test(2) {
    my $self = shift;
    my $foo  = 1;
    $self->test_comp(
        src => '
% my $ref = $.args->{ref};
% $m->add_cleanup(sub { $$ref++ });
foo = <% $$ref %>
',
        args   => { ref => \$foo },
        expect => 'foo = 1'
    );
    is( $foo, 2, "foo now 2" );
}

sub test_capture : Test(1) {
    my $self = shift;
    $self->run_test_in_comp(
        test => sub {
            my $comp = shift;
            my $m    = $comp->m;
            is( $m->capture( sub { print "abcde" } ), 'abcde' );
        }
    );
}

sub test_comp_exists : Test(1) {
    my $self = shift;

    $self->add_comp( path => '/comp_exists/one.m', src => 'hi' );
    $self->test_comp(
        path => '/comp_exists/two.m',
        src  => '
% foreach my $path (qw(/comp_exists/one.m /comp_exists/two.m /comp_exists/three.m one.m two.m three.m)) {
<% $path %>: <% $m->comp_exists($path) ? "yes" : "no" %>
% }
',
        expect => '
/comp_exists/one.m: yes
/comp_exists/two.m: yes
/comp_exists/three.m: no
one.m: yes
two.m: yes
three.m: no
',
    );
}

sub test_current_comp_class : Test(1) {
    shift->test_comp(
        path   => '/current_comp_class.m',
        src    => '<% ' . __PACKAGE__ . '::_get_current_comp_class($m)->cmeta->path %>',
        expect => '/current_comp_class.m'
    );
}

sub test_id : Test(3) {
    my $self = shift;
    $self->setup_dirs;
    $self->add_comp( path => '/id.m', src => 'id=<% $m->id %>' );
    my ($id1) = ( $self->interp->run('/id')->output =~ /id=(\d+)/ );
    my ($id2) = ( $self->interp->run('/id')->output =~ /id=(\d+)/ );
    ok( $id1 != $id2 );
}

sub test_log : Test(1) {
    my $self = shift;
    $self->add_comp( path => '/log/one.m', src => '% $m->log->info("message one")' );
    $self->run_test_in_comp(
        path => '/log.m',
        test => sub {
            my $comp = shift;
            my $m    = $comp->m;
            $m->comp('/log/one.m');
            $log->contains_ok("message one");
        },
    );
}

sub test_notes : Test(1) {
    my $self = shift;
    $self->add_comp(
        path => '/show',
        src  => '
<% $m->notes("foo") %>
% $m->notes("foo", 3);
',
    );
    $self->test_comp(
        src => '
% $m->notes("foo", 2);
<% $m->notes("foo") %>
<& /show &>
<% $m->notes("foo") %>
',
        expect => "2\n\n2\n\n3\n",
    );
}

sub test_page : Test(1) {
    my $self = shift;
    $self->add_comp( path => '/page/other.mi', src => '<% $m->page->cmeta->path %>' );
    $self->test_comp(
        path   => '/page/first.m',
        src    => '<% $m->page->cmeta->path %>; <& other.mi &>',
        expect => '/page/first.m; /page/first.m'
    );
}

sub test_result_data : Test(1) {
    my $self = shift;
    $self->test_comp(
        src         => '% $m->result->data->{color} = "red"',
        expect_data => { color => "red" }
    );
}

sub test_scomp : Test(2) {
    my $self = shift;
    $self->add_comp( path => '/str', src => 'abcde' );
    $self->run_test_in_comp(
        test => sub {
            my $comp = shift;
            my $m    = $comp->m;
            is( $m->scomp('/str'), 'abcde' );
            is( $m->capture( sub { $m->scomp('/str') } ), '' );
        }
    );
}

sub test_subrequest : Test(6) {
    my $self = shift;

    my $reset_id = sub { Mason::Request->_reset_next_id };

    $reset_id->();
    $self->add_comp(
        path => '/subreq/other.m',
        src  => '
id=<% $m->id %>
<% $m->page->cmeta->path %>
<% $m->request_path %>
<% Mason::Util::dump_one_line($m->request_args) %>
',
    );
    $self->test_comp(
        path => '/subreq/go.m',
        src  => '
This should not get printed.
<%perl>$m->go("/subreq/other", foo => 5);</%perl>',
        expect => '
id=1
/subreq/other.m
/subreq/other
{foo => 5}
',
    );
    $reset_id->();
    $self->test_comp(
        path => '/subreq/go_with_req_params.m',
        src  => '
This should not get printed.
<%perl>my $buf; $m->go({out_method => \$buf}, "/subreq/other", foo => 5)</%perl>',
        expect => '',
    );
    $reset_id->();
    $self->test_comp(
        path => '/subreq/visit.m',
        src  => '
begin
id=<% $m->id %>
<%perl>$m->visit("/subreq/other", foo => 5);</%perl>
id=<% $m->id %>
end
',
        expect => '
begin
id=0
id=1
/subreq/other.m
/subreq/other
{foo => 5}
id=0
end
',
    );
    $reset_id->();
    $self->test_comp(
        path => '/subreq/visit_with_req_params.m',
        src  => '
begin
id=<% $m->id %>
<%perl>my $buf; $m->visit({out_method => \$buf}, "/subreq/other", foo => 5); print uc($buf);</%perl>
id=<% $m->id %>
end
',
        expect => '
begin
id=0
ID=1
/SUBREQ/OTHER.M
/SUBREQ/OTHER
{FOO => 5}
id=0
end
',
    );
    my $buf;
    $reset_id->();
    my $result = $self->interp->run( { out_method => \$buf }, '/subreq/go' );
    is( $result->output, '', 'no output' );
    is(
        $buf, '
id=1
/subreq/other.m
/subreq/other
{foo => 5}
', 'output in buf'
    );
}

1;
