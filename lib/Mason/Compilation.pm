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
use Mason::Util qw(trim);
use strict;
use warnings;

# Passed attributes
has 'compiler' => ( required => 1, weak_ref => 1 );
has 'path'     => ( required => 1 );
has 'source_file' => ( required => 1 );

# Derived attributes
has 'dir_path' => ( lazy_build => 1, init_arg => undef );

method BUILD () {

    # Initialize state
    $self->{blocks} = {};
    $self->{source} = read_file( $self->source_file );
    $self->{source} =~ s/\r\n?/\n/g;
    $self->{ending}                = qr/\G\z/;
    $self->{in_method_block}       = undef;
    $self->{line_number}           = 1;
    $self->{methods}               = { main => $self->_new_method_hash( name => 'main' ) };
    $self->{current_method}        = $self->{methods}->{main};
    $self->{is_pure_perl}          = $self->compiler->is_pure_perl_comp_path( $self->path );
    $self->{filtered_method_count} = 0;
}

method _build_compilation_class () {
    return $self->compiler->interp->find_subclass('Compilation');
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
        $self->_match_apply_filter   && next;
        $self->_match_substitution   && next;
        $self->_match_component_call && next;
        $self->_match_perl_line      && next;
        $self->_match_plain_text     && next;

        $self->throw_syntax_error(
            "could not parse next element at position " . pos( $self->{source} ) );
    }
}

# Can be overriden to arbitrarily process Perl code in
# <%perl>, <%class>, <%init>, <% %>, and %-lines
#
method process_perl_code ($code) {
    $code = $self->dollar_dot_replacement($code);
    return $code;
}

# Replace $.foo with $self->foo()
#
method dollar_dot_replacement ($code) {
    $code =~ s/\$\.([^\W\d]\w*)/\$self->$1/g;
    return $code;
}

method _match_unnamed_block () {
    my $unnamed_block_regex = $self->compiler->unnamed_block_regex;
    $self->_match_block( qr/\G(\n?)<%($unnamed_block_regex)>/, 0 );
}

method _match_named_block () {
    my $named_block_regex = $self->compiler->named_block_regex;
    $self->_match_block(
        qr/
               \G(\n?)
               <% ($named_block_regex)
               (?: \s+ ([^\s\(>]+) ([^>]*) )?
               >
    /x, 1
    );
}

method _match_block ( $regex, $named ) {
    if ( $self->{source} =~ /$regex/gcs ) {
        my ( $preceding_newline, $block_type, $name, $arglist ) = ( $1, $2, $3, $4 );

        $self->throw_syntax_error("$block_type block requires a name")
          if ( $named && !defined($name) );

        $self->throw_syntax_error(
            "Cannot nest a $block_type block inside a $self->{in_block} block")
          if $self->{in_block};

        local $self->{in_block} = $block_type;

        my $block_method = "_handle_${block_type}_block";

        $self->{line_number}++ if $preceding_newline;

        my ( $block_contents, $nl ) = $self->_match_block_end($block_type);

        $self->$block_method( $block_contents, $name, $arglist );

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

method _match_apply_filter () {
    if ( $self->{source} =~ /\G(\n)? <% (.+?) (\s*\{\s*) %>(\n)?/xcgs ) {
        my ( $preceding_newline, $filter_expr, $closing_brace, $following_newline ) =
          ( $1, $2, $3, $4 );
        if ( $self->{source} =~ /\G (.*?) <% [ \t]* \} [ \t]* %>\s*(\n?\n?)/xcgs ) {
            my ( $contents, $following_newlines ) = ( $1, $2 );
            for ( $preceding_newline, $filter_expr, $following_newline ) {
                $self->{line_number} += tr/\n// if defined($_);
            }
            $self->_handle_apply_filter( $filter_expr, $contents );
            for ( $closing_brace, $contents, $following_newlines ) {
                $self->{line_number} += tr/\n//;
            }
            return 1;
        }
        else {
            $self->throw_syntax_error("<% { %> without matching <% } %>");
        }
    }
    else {
        return 0;
    }
}

method _match_substitution () {

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
            $self->_output_flag_comment, $self->_output_class_header, $self->_output_comp_info,
            $self->_output_attributes,   $self->_output_class_block,  $self->_output_methods,
        )
    ) . "\n";
}

method _output_attributes () {
    return $self->{blocks}->{attributes} || '';
}

method _output_flag_comment () {
    if ( my $flags = $self->{blocks}->{flags} ) {
        if (%$flags) {
            my $json = JSON->new->indent(0);
            return "# FLAGS: " . $json->encode($flags) . "\n\n";
        }
    }
}

method _output_class_header () {
    return join(
        "\n",
        "use Method::Signatures::Simple;",
        "use MooseX::HasDefaults::RW;",
        "use strict;",
        "use warnings;",
        "no warnings 'redefine';",

        # Must be defined here since inner relies on caller()
        "sub comp_inner { inner() }"
    );
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
    return join( "\n",
        map { $self->_output_method( $self->{methods}->{$_} ) }
        sort( keys( %{ $self->{methods} } ) ) );
}

method _output_method ($method) {
    my $path = $self->path;

    my $name     = $method->{name};
    my $modifier = $method->{modifier};
    my $arglist  = $method->{arglist} || '';
    my $contents = join( "\n", grep { /\S/ } ( $method->{init}, $method->{body} ) );

    my $start =
        $modifier ? "$modifier '$name' => sub {"
      : $arglist  ? "method $name $arglist {"
      :             "sub $name {";
    my $end = $modifier ? "};" : "}";

    return join(
        "\n",
        $start,
        $arglist ? "" : "my \$self = shift;",
        "my \$m = \$self->m;",

        "my \$_buffer = \$m->_current_buffer;",

        # do not add a block around this, it introduces
        # a separate scope and might break cleanup
        # blocks (or all sort of other things!)
        $contents,

        # don't return values explicitly. semi before return will help catch
        # syntax errors in component body.
        ";return;",
        $end,
    );
}

method _output_line_number_comment ($line_number) {
    if ( !$self->compiler->no_source_line_numbers ) {
        $line_number ||= $self->{line_number};
        if ($line_number) {
            my $comment = sprintf( qq{#line %s "%s"\n}, $line_number, $self->source_file );
            return $comment;
        }
    }
    return "";
}

method _handle_attr_block ($contents) {
    $self->_handle_attributes_list( $contents, 'attr' );
}

method _handle_shared_block ($contents) {
    $self->_handle_attributes_list( $contents, 'shared' );
}

method _handle_attributes_list ($contents, $attr_type) {
    my @lines = split( "\n", $contents );
    my @attributes;
    my $line_number = $self->{line_number} - 1;
    foreach my $line (@lines) {
        $line_number++;
        trim($line);
        next if $line =~ /^\#/ || $line !~ /\S/;
        if (
            my ( $name, $rest ) = (
                $line =~ /
                          (?: \$\.)?        # optional $. prefix
                          ([^\W\d]\w*)      # valid Perl variable name
                          (?:\s*=>\s*(.*))? # optional arrow then default or attribute params
                         /x
            )
          )
        {
            my ($params);
            if ( defined($rest) && length($rest) ) {
                if ( $rest =~ /^\s*\(/ ) {
                    $params = "$rest\n;";
                }
                else {
                    $params = sprintf( "(default => %s\n);", $rest );
                }
            }
            else {
                $params = $attr_type eq 'attr' ? "(required => 1);" : "();";
            }
            if ( $attr_type eq 'shared' ) {
                $params = '(' . 'init_arg => undef, ' . substr( $params, 1 );
            }
            push( @attributes, $self->_attribute_declaration( $name, $params, $line_number ) );
        }
        else {
            $self->throw_syntax_error("Invalid attribute line '$line'");
        }
    }
    $self->{blocks}->{attributes} .= join( "\n", @attributes ) . "\n";
}

method _attribute_declaration ($name, $params, $line_number) {
    return $self->process_perl_code(
        sprintf(
            "%shas '%s' => %s",
            $self->_output_line_number_comment($line_number),
            $name, $params
        )
    );
}

method _handle_class_block ($contents) {
    $self->_assert_not_in_method('<%class>');
    $self->{blocks}->{class} =
      $self->_output_line_number_comment . $self->process_perl_code($contents);
}

method _handle_init_block ($contents) {
    $self->{current_method}->{init} =
      $self->_output_line_number_comment . $self->process_perl_code($contents);
}

# Save current regex position, then locally set source to the contents and
# recursively parse.
#
method _recursive_parse ($contents, $method_key) {
    my $save_pos = pos( $self->{source} );
    scope_guard { pos( $self->{source} ) = $save_pos };
    {
        local $self->{source}          = $contents;
        local $self->{current_method}  = $self->{methods}->{$method_key};
        local $self->{in_method_block} = $method_key;

        $self->parse();
    }
}

method _handle_apply_filter ($filter_expr, $contents) {
    my $anon_name = "_filtered_" . $self->{filtered_method_count}++;
    $self->{methods}->{$anon_name} = $self->_new_method_hash( name => $anon_name );
    $self->_recursive_parse( $contents, $anon_name );
    my $code = sprintf(
        "\$self->m->_apply_filter(\$self, %s, sub {\nmy \$_buffer = \$m->_current_buffer;\n%s \n});\n",
        $self->process_perl_code($filter_expr),
        $self->{methods}->{$anon_name}->{body}
    );
    delete( $self->{methods}->{$anon_name} );
    $self->_add_to_current_method($code);
}

method _handle_method_block ( $contents, $name, $arglist ) {
    $self->_assert_not_in_method("<%method>");

    $self->throw_syntax_error("Invalid method name '$name'")
      if $name =~ /[^\w]/;

    $self->throw_syntax_error("Duplicate definition of method '$name'")
      if exists $self->{methods}->{$name};

    $self->{methods}->{$name} = $self->_new_method_hash( name => $name, arglist => $arglist );

    $self->_recursive_parse( $contents, $name );
}

method _handle_after_block ()  { $self->_handle_method_modifier_block( 'after',  @_ ) }
method _handle_around_block () { $self->_handle_method_modifier_block( 'around', @_ ) }
method _handle_wrap_block ()   { $self->_handle_method_modifier_block( 'wrap',   @_ ) }
method _handle_before_block () { $self->_handle_method_modifier_block( 'before', @_ ) }

method _handle_method_modifier_block ( $block_type, $contents, $name ) {
    my $modifier = ( $block_type eq 'wrap' ? 'augment' : $block_type );

    $self->_assert_not_in_method("<%$block_type>");

    $self->throw_syntax_error("Invalid method modifier name '$name'")
      if $name =~ /[^\w]/;

    my $method_key = "$block_type $name";

    $self->throw_syntax_error("Duplicate definition of method modifier '$method_key'")
      if exists $self->{method}->{"$method_key"};

    $self->{methods}->{"$method_key"} =
      $self->_new_method_hash( name => $name, modifier => $modifier );

    $self->_recursive_parse( $contents, $method_key );
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
    $self->_add_to_current_method( $self->process_perl_code($contents) );

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

    $text = $self->process_perl_code($text);

    my $code = "{ no warnings 'uninitialized'; \$\$_buffer .= $text }\n";

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
    my $code = $self->process_perl_code( $contents . "\n" );

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
    return { body => '', init => '', @_ };
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
