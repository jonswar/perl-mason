package Blog::DB;
use Cwd qw(realpath);
use File::Basename;
use strict;
use warnings;
use base qw(Rose::DB);

my $root_dir = dirname(dirname(dirname(realpath(__FILE__))));

__PACKAGE__->use_private_registry;
__PACKAGE__->register_db(
    driver   => 'sqlite',
    database => "$root_dir/data/blog.db",
);

1;
