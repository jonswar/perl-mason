#!/bin/bash

# Requires cpanm: http://search.cpan.org/perldoc?App::cpanminus
cpanm -S Date::Format DBD::SQLite Mason Mason::Plugin::PSGIHandler
cpanm -S Plack Plack::Middleware::Session Rose::DB::Object

sqlite3 data/blog.db < blog.sql
