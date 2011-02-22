#!/bin/bash

# Requires cpanm: http://search.cpan.org/perldoc?App::cpanminus
cpanm -S Date::Format DBD::SQLite Mason Mason::Plugin::PSGIHandler Mason::Plugin::HTMLFilters
cpanm -S Plack Plack::Middleware::Session Rose::DB::Object

mkdir -p data
sqlite3 data/blog.db < blog.sql
