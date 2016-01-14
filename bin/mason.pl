#!/usr/bin/perl

use strict;
use warnings;
use Mason::App;
Mason::App->run();

__END__

=head1 NAME

mason.pl - evaluate a mason template and output the result

=head1 SYNOPSIS

   # Evaluate template from STDIN
   mason.pl [mason options] [--args json-string]

   # Evaluate template in string
   mason.pl [mason options] [--args json-string] -e "string"

   # Evaluate template in file
   mason.pl [mason options] [--args json-string] template-file

=head1 DESCRIPTION

Reads a Mason template (component) from STDIN, a string, or a file. Runs the
template and outputs the result to STDOUT.

=head1 MASON OPTIONS

The following Mason options can be specified on the command line:

    --data-dir /path/to/data_dir
    --plugins MyPlugin,MyOtherPlugin

The C<comp_root> will be set to the directory of the template file or to a
temporary directory if using STDIN. If not specified C<data_dir> will be set to
a temporary directory.

=head1 ADDITIONAL OPTIONS

=over

=item --args json-string

A hash of arguments to pass to the page component, in JSON form. e.g.

    --args '{"count":5,"names":["Alice","Bob"]}'

=back

=head1 SEE ALSO

L<Mason|Mason>

=head1 AUTHOR

Jonathan Swartz <swartz@pobox.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011-2015 by Jonathan Swartz.

This is free software; you can redistribute it and/or modify it under the same
terms as the Perl 5 programming language system itself.

=cut
