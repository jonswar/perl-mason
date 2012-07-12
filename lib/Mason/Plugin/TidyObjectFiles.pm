package Mason::Plugin::TidyObjectFiles;
use Moose;
with 'Mason::Plugin';

__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

Mason::Plugin::TidyObjectFiles - Tidy object files

=head1 DESCRIPTION

Uses perltidy to tidy object files (the compiled form of Mason components).

=head1 ADDITIONAL PARAMETERS

=over

=item tidy_options

A string of perltidy options. e.g.

    tidy_options => '-noll -l=72'

    tidy_options => '--pro=/path/to/.perltidyrc'

May include --pro/--profile to point to a .perltidyrc file. If omitted, will
use default perltidy settings.

=back
