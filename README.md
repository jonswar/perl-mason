# Mason

Mason - Powerful, high-performance templating for the web and beyond

## Synopsis

    foo.mc:
       % my $name = "Mason";
       Hello world! Welcome to <% $name %>.

    #!/usr/bin/env perl
    use Mason;
    my $mason = Mason->new(comp_root => '...');
    print $mason->run('/foo')->output;

## Installation from CPAN

    cpanm Mason

## Installtion from source

    git clone https://github.com/jonswar/perl-mason.git
    cd perl-mason
    cpanm Dist::Zilla  # ensure DistZilla is installed
    dzil -Ilib authordeps --missing | cpanm --no-skip-satisfied

## Documentation

Introductory documentation is available via

    perldoc Mason

Detailed documentation is available in the Mason manual:

    perldoc Mason::Manual
