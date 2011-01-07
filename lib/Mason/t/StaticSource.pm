package Mason::t::StaticSource;
use Test::Class::Most parent => 'Mason::Test::Class';
use File::Slurp;
use Mason::Util qw(touch_file);

sub setup : Test(setup) {
    my ($self) = @_;

    $self->setup_dirs();
    $self->add_comp(
        path => "/ss/remove_component.m",
        src  => "I will be removed.\n",
    );
    $self->add_comp(
        path => "/ss/change_component.m",
        src  => "I will be changed.\n",
    );
}

sub write_comp {
    my ( $self, $path, $contents ) = @_;
    my $source_file = $self->{interp}->load($path)->cmeta->source_file;
    write_file( $source_file, $contents );
}

sub remove_comp {
    my ( $self, $path ) = @_;
    my $source_file = $self->{interp}->load($path)->cmeta->source_file;
    unlink($source_file);
}

sub test_change_no_ss : Test(2) {
    my $self = shift;
    $self->test_comp(
        src    => '<& /ss/change_component.m &>',
        expect => 'I will be changed.',
    );
    sleep(1);    # Make sure timestamp changes
    $self->write_comp( "/ss/change_component.m", "I have changed!\n" );
    $self->test_comp(
        src    => '<& /ss/change_component.m &>',
        expect => 'I have changed!',
    );
}

sub test_change_and_touch_ss : Test(3) {
    my $self       = shift;
    my $touch_file = $self->{temp_dir} . "/purge.dat";
    $self->{interp} =
      $self->create_interp( static_source => 1, static_source_touch_file => $touch_file );
    $self->test_comp(
        src    => '<& /ss/change_component.m &>',
        expect => 'I will be changed.',
    );
    sleep(1);    # Make sure timestamp changes
    $self->write_comp( "/ss/change_component.m", "I have changed!\n" );
    $self->test_comp(
        src    => '<& /ss/change_component.m &>',
        expect => 'I will be changed.',
    );
    touch_file($touch_file);
    $self->test_comp(
        src    => '<& /ss/change_component.m &>',
        expect => 'I have changed!',
    );
}

sub test_remove_no_ss : Test(2) {
    my $self = shift;
    $self->test_comp(
        src    => '<& /ss/remove_component.m &>',
        expect => 'I will be removed.',
    );
    $self->remove_comp("/ss/remove_component.m");
    $self->test_comp(
        src          => '<& /ss/remove_component.m &>',
        expect_error => qr/could not find component/
    );
}

sub test_remove_and_touch_ss : Test(3) {
    my $self       = shift;
    my $touch_file = $self->{temp_dir} . "/purge.dat";
    $self->{interp} =
      $self->create_interp( static_source => 1, static_source_touch_file => $touch_file );
    $self->test_comp(
        src    => '<& /ss/remove_component.m &>',
        expect => 'I will be removed.',
    );
    $self->remove_comp("/ss/remove_component.m");
    $self->test_comp(
        src    => '<& /ss/remove_component.m &>',
        expect => 'I will be removed.',
    );
    touch_file($touch_file);
    $self->test_comp(
        src          => '<& /ss/remove_component.m &>',
        expect_error => qr/could not find component/
    );
}

1;
