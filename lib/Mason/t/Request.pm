package Mason::t::Request;
use Test::Class::Most parent => 'Mason::Test::Class';
use Log::Any::Adapter;
use Test::Log::Dispatch;

sub _get_current_comp_class {
    my $m = shift;
    return $m->current_comp_class;
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
    is( $self->interp->run('/id')->output, "id=0" );
    is( $self->interp->run('/id')->output, "id=1" );
    is( $self->interp->run('/id')->output, "id=2" );
}

sub test_log : Test(2) {
    my $self = shift;
    my $log = Test::Log::Dispatch->new( min_level => 'debug' );
    Log::Any::Adapter->set( { category => 'Mason::Component::log::one.m', lexically => \my $lex },
        'Dispatch', dispatcher => $log );
    $self->add_comp( path => '/log/one.m', src => '% $m->log->info("message one")' );
    $self->add_comp( path => '/log/two.m', src => '% $m->log->info("message two")' );
    $self->run_test_in_comp(
        path => '/log.m',
        test => sub {
            my $comp = shift;
            my $m    = $comp->m;
            $m->comp('/log/one.m');
            $m->comp('/log/two.m');
            $log->contains_ok("message one");
            $log->does_not_contain_ok("message two");
        },
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

sub test_subrequest : Test(4) {
    my $self = shift;

    # call setup_interp each time to reset request count
    #
    $self->setup_interp;
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
    $self->setup_interp;    # reset request id
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
    my $buf;
    $self->setup_interp;    # reset request id
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
