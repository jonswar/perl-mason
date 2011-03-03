package Mason::t::Request;
use Test::Class::Most parent => 'Mason::Test::Class';
use Log::Any::Test;
use Log::Any qw($log);

sub _get_current_comp_class {
    my $m = shift;
    return $m->current_comp_class;
}

sub test_add_cleanup : Tests {
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

sub test_capture : Tests {
    my $self = shift;
    $self->run_test_in_comp(
        test => sub {
            my $comp = shift;
            my $m    = $comp->m;
            is( $m->capture( sub { print "abcde" } ), 'abcde' );
        }
    );
}

sub test_comp_exists : Tests {
    my $self = shift;

    $self->add_comp( path => '/comp_exists/one.mc', src => 'hi' );
    $self->test_comp(
        path => '/comp_exists/two.mc',
        src  => '
% foreach my $path (qw(/comp_exists/one.mc /comp_exists/two.mc /comp_exists/three.mc one.mc two.mc three.mc)) {
<% $path %>: <% $m->comp_exists($path) ? "yes" : "no" %>
% }
',
        expect => '
/comp_exists/one.mc: yes
/comp_exists/two.mc: yes
/comp_exists/three.mc: no
one.mc: yes
two.mc: yes
three.mc: no
',
    );
}

sub test_current_comp_class : Tests {
    shift->test_comp(
        path   => '/current_comp_class.mc',
        src    => '<% ' . __PACKAGE__ . '::_get_current_comp_class($m)->cmeta->path %>',
        expect => '/current_comp_class.mc'
    );
}

sub test_id : Tests {
    my $self = shift;
    $self->setup_dirs;
    $self->add_comp( path => '/id.mc', src => 'id=<% $m->id %>' );
    my ($id1) = ( $self->interp->run('/id')->output =~ /id=(\d+)/ );
    my ($id2) = ( $self->interp->run('/id')->output =~ /id=(\d+)/ );
    ok( $id1 != $id2 );
}

sub test_log : Tests {
    my $self = shift;
    $self->add_comp( path => '/log/one.mc', src => '% $m->log->info("message one")' );
    $self->run_test_in_comp(
        path => '/log.mc',
        test => sub {
            my $comp = shift;
            my $m    = $comp->m;
            $m->comp('/log/one.mc');
            $log->contains_ok("message one");
        },
    );
}

sub test_notes : Tests {
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

sub test_page : Tests {
    my $self = shift;
    $self->add_comp( path => '/page/other.mi', src => '<% $m->page->cmeta->path %>' );
    $self->test_comp(
        path   => '/page/first.mc',
        src    => '<% $m->page->cmeta->path %>; <& other.mi &>',
        expect => '/page/first.mc; /page/first.mc'
    );
}

sub test_result_data : Tests {
    my $self = shift;
    $self->test_comp(
        src         => '% $m->result->data->{color} = "red"',
        expect_data => { color => "red" }
    );
}

sub test_scomp : Tests {
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

sub test_subrequest : Tests {
    my $self = shift;

    my $reset_id = sub { Mason::Request->_reset_next_id };

    $reset_id->();
    $self->add_comp(
        path => '/subreq/other.mc',
        src  => '
id=<% $m->id %>
<% $m->page->cmeta->path %>
<% $m->request_path %>
<% Mason::Util::dump_one_line($m->request_args) %>
',
    );
    $self->test_comp(
        path => '/subreq/go.mc',
        src  => '
This should not get printed.
<%perl>$m->go("/subreq/other", foo => 5);</%perl>',
        expect => '
id=1
/subreq/other.mc
/subreq/other
{foo => 5}
',
    );
    $reset_id->();
    $self->test_comp(
        path => '/subreq/go_with_req_params.mc',
        src  => '
This should not get printed.
<%perl>my $buf; $m->go({out_method => \$buf}, "/subreq/other", foo => 5)</%perl>',
        expect => '',
    );
    $reset_id->();
    $self->test_comp(
        path => '/subreq/visit.mc',
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
/subreq/other.mc
/subreq/other
{foo => 5}
id=0
end
',
    );
    $reset_id->();
    $self->test_comp(
        path => '/subreq/visit_with_req_params.mc',
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
/SUBREQ/OTHER.MC
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
/subreq/other.mc
/subreq/other
{foo => 5}
', 'output in buf'
    );
}

1;
