package Blog::Article;
use Blog::DB;
use strict;
use warnings;
use base qw(Rose::DB::Object);

__PACKAGE__->meta->setup(
    table => 'articles',
    auto  => 1,
);
__PACKAGE__->meta->make_manager_class('articles');
sub init_db { Blog::DB->new }

1;
