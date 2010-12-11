# Copyright (c) 1998-2005 by Jonathan Swartz. All rights reserved.
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.

package Mason::Compilation;
use File::Basename qw(dirname);
use Guard;
use JSON;
use Mason::Util qw(dump_one_line read_file unique_id);
use Method::Signatures::Simple;
use Moose;
use Mason::Moose;
use Text::Trim qw(trim);
use strict;
use warnings;

# Passed attributes
has 'compiler' => ( required => 1, weak_ref => 1 );
has 'interp'   => ( required => 1 );
has 'path'     => ( required => 1 );
has 'source_file' => ( required => 1 );

# Derived attributes
has 'dir_path' => ( lazy_build => 1, init_arg => undef );

method BUILD () {

    # Initialize state
    $self->{blocks} = {};
    $self->{source} = read_file( $self->source_file );
    $self->{source} =~ s/\r\n?/\n/g;
    $self->{ending}          = qr/\G\z/;
    $self->{in_method_block} = undef;
    $self->{line_number}     = 1;
    $self->{methods}         = { main => $self->_new_method_hash() };
    $self->{current_method}  = $self->{methods}->{main};
    $self->{is_pure_perl}    = $self->compiler->is_pure_perl_comp_path( $self->path );
}

method _build_dir_path () {
    return dirname( $self->path );
}

# Parse the component source, or a single method block body
#
method parse () {
    $self->{in_block}       = undef;
    $self->{last_code_type} = '';

    if ( $self->{is_pure_perl} ) {
        $self->{source} = "<%class> " . $self->{source} . " </%class>";
        delete( $self->{methods}->{main} );
    }

    while (1) {
        $self->_match_end            && last;
        $self->_match_unnamed_block  && next;
        $self->_match_named_block    && next;
        $self->_match_substitution   && next;
        $self->_match_component_call && next;
        $self->_match_perl_line      && next;
        $self->_match_plain_text     && next;

        $self->throw_syntax_error(
            "could not parse next element at position " . pos( $self->{source} ) );
    }

    if ( $self->{is_pure_perl} ) {
    }
}

method _match_unnamed_block () {
    my $block_regex = $self->compiler->block_regex;
    $self->_match_block( qr/\G(\n?)<%($block_regex)>/, 0 );
}

method _match_named_block () {
    $self->_match_block( qr/\G(\n?)<%(method)(?:\s+([^\n^>]+))?>/, 1 );
}

method _match_block ( $regex, $named ) {
    if ( $self->{source} =~ /$regex/gcs ) {
        my ( $preceding_newline, $block_type, $name ) = ( $1, $2, $3 );

        $self->throw_syntax_error("$block_type block requires a name")
          if ( $named && !defined($name) );

        $self->throw_syntax_error(
            "Cannot nest a $block_type block inside a $self->{in_block} block")
          if $self->{in_block};

        local $self->{in_block} = $block_type;

        my $block_method = "_handle_${block_type}_block";

        $self->{line_number}++ if $preceding_newline;

        my ( $block_contents, $nl ) = $self->_match_block_end($block_type);

        $self->$block_method( $block_contents, $name );

        $self->{line_number} += $block_contents =~ tr/\n//;
        $self->{line_number} += length($nl) if $nl;

        return 1;
    }
    return 0;
}

method _match_block_end ($block_type) {
    my $re = qr,\G(.*?)</%\Q$block_type\E>(\n?\n?),is;
    if ( $self->{source} =~ /$re/gc ) {
        return ( $1, $2 );
    }
    else {
        $self->throw_syntax_error("<%$block_type> without matching </%$block_type>");
    }
}

method _match_substitution () {

    # This routine relies on there *not* to be an opening <%foo> tag
    # present, so _match_block() must happen first.

    return 0 unless $self->{source} =~ /\G<%/gcs;

    my $flag = $self->compiler->escape_flag_regex();
    if (
        $self->{source} =~ m{
           \G
           (.+?)                # Substitution body ($1)
           (
            \s*
            (?<!\|)             # Not preceded by a '|'
            \|                  # A '|'
            \s*
            (                   # (Start $3)
             $flag              # A flag
             (?:\s*,\s*$flag)*  # More flags, with comma separators
            )
            \s*
           )?
           %>                   # Closing tag
          }xcigs
      )
    {
        $self->{line_number} += tr/\n// foreach grep defined, ( $1, $2 );

        $self->_handle_substitution( $1, $3 );

        return 1;
    }
    else {
        $self->throw_syntax_error("'<%' without matching '%>'");
    }
}

method _match_component_call () {
    if ( $self->{source} =~ /\G<&(?!\|)/gcs ) {
        if ( $self->{source} =~ /\G(.*?)&>/gcs ) {
            my $body = $1;
            $self->_handle_component_call($body);
            $self->{line_number} += $body =~ tr/\n//;

            return 1;
        }
        else {
            $self->throw_syntax_error("'<&' without matching '&>'");
        }
    }
}

method _match_perl_line () {
    if ( $self->{source} =~ /\G(?<=^)%([^\n]*)(?:\n|\z)/gcm ) {
        my $line = $1;
        if ( $line !~ /^\s/ ) {
            $self->throw_syntax_error("% must be followed by whitespace");
        }
        $self->_handle_perl_line($line);
        $self->{line_number}++;

        return 1;
    }
}

method _match_plain_text () {

    # Most of these terminator patterns actually belong to the next
    # lexeme in the source, so we use a lookahead if we don't want to
    # consume them.  We use a lookbehind when we want to consume
    # something in the matched text, like the newline before a '%'.

    if (
        $self->{source} =~ m{
                                \G
                                (.*?)         # anything, followed by:
                                (
                                 (?<=\n)(?=%) # an eval line - consume the \n
                                 |
                                 (?=<%\s)     # a substitution tag
                                 |
                                 (?=</?[%&])  # a block or call start or end
                                              # - don't consume
                                 |
                                 \\\n         # an escaped newline  - throw away
                                 |
                                 \z           # end of string
                                )
                               }xcgs
      )
    {
        my ( $orig_text, $swallowed ) = ( $1, $2 );
        my $text = $orig_text;

        # Chomp newline before block start
        #
        if ( substr( $self->{source}, pos( $self->{source} ), 3 ) =~ /<%[a-z]/ ) {
            chomp($text);
        }
        $self->_handle_plain_text($text) if length $text;

        # Not checking definedness seems to cause extra lines to be
        # counted with Perl 5.00503.  I'm not sure why - dave
        $self->{line_number} += tr/\n// foreach grep defined, ( $orig_text, $swallowed );

        return 1;
    }

    return 0;
}

method _match_end () {

    # $self->{ending} is a qr// 'string'.  No need to escape.  It will
    # also include the needed \G marker
    if ( $self->{source} =~ /($self->{ending})/gcs ) {
        $self->{line_number} += $1 =~ tr/\n//;
        return defined $1 && length $1 ? $1 : 1;
    }
    return 0;
}

method compile () {
    $self->parse();
    return $self->output_compiled_component();
}

method output_compiled_component () {
    return join(
        "\n",
        map { trim($_) } grep { defined($_) && length($_) } (
            $self->_output_flag_comment, $self->_output_use_vars,    $self->_output_strictures,
            $self->_output_comp_info,    $self->_output_class_block, $self->_output_methods,
        )
    ) . "\n";
}

method _output_flag_comment () {
    if ( my $flags = $self->{blocks}->{flags} ) {
        if (%$flags) {
            my $json = JSON->new->indent(0);
            return "# FLAGS: " . $json->encode($flags) . "\n\n";
        }
    }
}

method _output_use_vars () {
    my @allow_globals = @{ $self->compiler->allow_globals };
    return @allow_globals
      ? sprintf( "use vars qw(%s);", join( ' ', @allow_globals ) )
      : "";
}

method _output_strictures () {
    return join( "\n", "no warnings 'redefine';" );
}

method _output_comp_info () {
    my %comp_info = (
        comp_dir_path    => $self->dir_path,
        comp_path        => $self->path,
        comp_is_external => $self->compiler->is_external_comp_path( $self->path ),
    );
    return sprintf( 'sub _comp_info { return %s }', dump_one_line( \%comp_info ) );
}

method _output_class_block () {
    return $self->{blocks}->{'class'} || '';
}

method _output_methods () {
    return join(
        "\n", map { $self->_output_method($_) }
          sort( keys( %{ $self->{methods} } ) )
    );
}

method _output_method ($method_name) {
    my $path = $self->path;

    my $method = $self->{methods}->{$method_name};
    my $contents = join( "\n", grep { /\S/ } ( $method->{init}, $method->{body} ) );
    my $filter_sub;
    if ( $method->{filter} ) {
        $filter_sub = join( "\n", 'sub { local $_ = $_[0];', $method->{filter}, 'return $_ }' );
    }

    return join(
        "\n",
        "sub $method_name {",
        "my \$self = shift;",
        "my \$m = \$self->m;",

        $filter_sub ? "\$m->apply_immediate_filter($filter_sub, sub {" : "",

        "my \$_buffer = \$m->current_buffer;",

        # do not add a block around this, it introduces
        # a separate scope and might break cleanup
        # blocks (or all sort of other things!)
        $contents,

        $filter_sub ? "});" : "",

        # don't return values explicitly. semi before return will help catch
        # syntax errors in component body.
        ";return;",
        "}",
    );
}

method _output_line_number_comment () {
    if ( !$self->compiler->no_source_line_numbers ) {
        if ( my $line = $self->{line_number} ) {
            my $comment = sprintf( qq{ #line %s "%s"\n}, $line, $self->source_file );
            return $comment;
        }
    }
    return "";
}

method _handle_class_block ($contents) {
    $self->_assert_not_in_method('<%class>');
    $self->{blocks}->{class} = $self->_output_line_number_comment . $contents;
}

method _handle_init_block ($contents) {
    $self->{current_method}->{init} = $self->_output_line_number_comment . $contents;
}

method _handle_method_block ( $contents, $name ) {
    $self->_assert_not_in_method('<%method>');

    $self->throw_syntax_error("Invalid method name '$name'")
      if $name =~ /[^.\w-]/;

    $self->throw_syntax_error("Duplicate definition of method '$name'")
      if exists $self->{methods}->{$name};

    $self->{methods}->{$name} = $self->_new_method_hash();

    # Save current regex position, then locally set source to the method's
    # contents and recursively parse.
    #
    my $save_pos = pos( $self->{source} );
    scope_guard { pos( $self->{source} ) = $save_pos };
    {
        local $self->{source}          = $contents;
        local $self->{current_method}  = $self->{methods}->{$name};
        local $self->{in_method_block} = $name;

        $self->parse();
    }
}

method _handle_doc_block () {

    # Don't do anything - just discard the comment.
}

method _handle_filter_block ($contents) {
    $self->{current_method}->{filter} = $self->_output_line_number_comment . $contents;
}

method _handle_flags_block ($contents) {
    my $ending = qr, (?: \n |           # newline or
                         (?= </%flags> ) )   # end of block (don't consume it)
                   ,ix;

    while (
        $contents =~ /
                      \G
                      [ \t]*
                      ([\w_]+)          # identifier
                      [ \t]*=>[ \t]*    # separator
                      (\S[^\n]*?)       # value ( must start with a non-space char)
                      $ending
                      |
                      \G\n              # a plain empty line
                      |
                      \G
                      [ \t]*            # an optional comment
                      \#
                      [^\n]*
                      $ending
                      |
                      \G[ \t]+?
                      $ending
                     /xgc
      )
    {
        my ( $flag, $value ) = ( $1, $2 );
        if ( defined $flag && defined $value && length $flag && length $value ) {
            if ( $self->compiler->valid_flags_hash->{$flag} ) {
                $self->{blocks}->{flags}->{$flag} = eval($value);
                die $@ if $@;
            }
            else {
                $self->throw_syntax_error("Invalid flag '$flag'");
            }
        }
    }
}

method _handle_perl_block ($contents) {
    $self->_add_to_current_method($contents);

    $self->{last_code_type} = 'perl_block';
}

method _handle_text_block ($contents) {
    $contents =~ s,([\'\\]),\\$1,g;

    $self->_add_to_current_method("\$\$_buffer .= '$contents';\n");

    $self->{last_code_type} = 'text';
}

method _handle_substitution ( $text, $escape ) {

    # This is a comment tag if all lines of text contain only whitespace
    # or start with whitespace and a comment marker, e.g.
    #
    #   <%
    #     #
    #     # foo
    #   %>
    #
    my @lines = split( /\n/, $text );
    unless ( grep { /^\s*[^\s\#]/ } @lines ) {
        $self->{last_code_type} = 'substitution';
        return;
    }

    if ( ( defined $escape )
        || @{ $self->compiler->default_escape_flags } )
    {
        my @flags;
        if ( defined $escape ) {
            $escape =~ s/\s+$//;

            @flags = split /\s*,\s*/, $escape;
        }

        # is there any way to check the flags for validity and still
        # allow them to be dynamically set from components?

        unshift @flags, @{ $self->compiler->default_escape_flags }
          unless grep { $_ eq 'n' } @flags;

        my %seen;
        my $flags = (
            join ', ', map { $seen{$_}++ ? () : "'$_'" }
              grep { $_ ne 'n' } @flags
        );

        $text = "\$m->apply_escapes( (join '', ($text)), $flags )"
          if $flags;
    }

    my $code = "for ( $text ) { \$\$_buffer .= \$_ if defined }\n";

    $self->_add_to_current_method($code);

    $self->{last_code_type} = 'substitution';
}

method _handle_component_call ($contents) {
    my ( $prespace, $call, $postspace ) = ( $contents =~ /(\s*)(.*)(\s*)/s );
    if ( $call =~ m,^[\w/.], ) {
        my $comma = index( $call, ',' );
        $comma = length $call if $comma == -1;
        ( my $comp = substr( $call, 0, $comma ) ) =~ s/\s+$//;
        $call = "'$comp'" . substr( $call, $comma );
    }
    my $code = "\$m->comp( $prespace $call $postspace \n); ";

    $self->_add_to_current_method($code);

    $self->{last_code_type} = 'component_call';
}

method _handle_perl_line ($contents) {
    my $code = "$contents\n";

    $self->_add_to_current_method($code);

    $self->{last_code_type} = 'perl_line';
}

method _handle_plain_text ($text) {

    # Escape single quotes and backslashes
    #
    $text =~ s,([\'\\]),\\$1,g;

    my $code = "\$\$_buffer .= '$text';\n";
    $self->_add_to_current_method($code);
}

method _assert_not_in_method ($entity) {
    if ( $self->{in_method_block} ) {
        $self->throw_syntax_error("$entity not permitted inside <%method> block");
    }
}

method _new_method_hash () {
    return { body => '', init => '' };
}

method _add_to_current_method ($text) {

    # Don't add a line number comment when following a perl-line.
    # We know a perl-line is always _one_ line, so we know that the
    # line numbers are going to match up as long as the first line in
    # a series has a line number comment before it.  Adding a comment
    # can break certain constructs like qw() list that spans multiple
    # perl-lines.
    if ( $self->{last_code_type} ne 'perl_line' ) {
        $text = $self->_output_line_number_comment . $text;
    }

    $self->{current_method}->{body} .= $text;
}

method throw_syntax_error ($msg) {
    die sprintf( "%s at %s line %d\n", $msg, $self->source_file, $self->{line_number} );
}

1;
