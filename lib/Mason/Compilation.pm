# Copyright (c) 1998-2005 by Jonathan Swartz. All rights reserved.
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.

package Mason::Compilation;
use File::Basename qw(dirname);
use Guard;
use Mason::Component::ClassMeta;
use Mason::Util qw(dump_one_line json_encode read_file taint_is_on trim);
use Mason::Moose;

# Passed attributes
has 'interp'      => ( required => 1, weak_ref => 1 );
has 'path'        => ( required => 1 );
has 'source_file' => ( required => 1 );

# Derived attributes - most of these should be class attributes :(
has 'bad_attribute_hash'  => ( lazy_build => 1, init_arg => undef );
has 'bad_method_hash'     => ( lazy_build => 1, init_arg => undef );
has 'dir_path'            => ( lazy_build => 1, init_arg => undef );
has 'named_block_regex'   => ( lazy_build => 1, init_arg => undef );
has 'unnamed_block_regex' => ( lazy_build => 1, init_arg => undef );
has 'valid_flags_hash'    => ( lazy_build => 1, init_arg => undef );

# Valid Perl identifier
my $identifier = qr/[[:alpha:]_]\w*/;

#
# BUILD
#

method BUILD () {

    # Initialize state
    $self->{blocks}          = {};
    $self->{blocks}->{class} = '';
    $self->{source}          = read_file( $self->source_file );
    $self->{source} =~ s/\r\n?/\n/g;
    $self->{line_number}    = 1;
    $self->{methods}        = { main => $self->_new_method_hash( name => 'main' ) };
    $self->{current_method} = $self->{methods}->{main};
    $self->{is_pure_perl}   = $self->interp->is_pure_perl_comp_path( $self->path );
}

method _build_bad_attribute_hash () {
    return { map { ( $_, 1 ) } @{ $self->bad_attribute_names } };
}

method _build_bad_method_hash () {
    return { map { ( $_, 1 ) } @{ $self->bad_method_names } };
}

method _build_dir_path () {
    return dirname( $self->path );
}

method _build_named_block_regex () {
    my $re = join '|', @{ $self->named_block_types };
    return qr/$re/i;
}

method _build_unnamed_block_regex () {
    my $re = join '|', @{ $self->unnamed_block_types };
    return qr/$re/i;
}

method _build_valid_flags_hash () {
    return { map { ( $_, 1 ) } @{ $self->valid_flags } };
}

#
# MODIFIABLE METHODS
#

method bad_attribute_names () {
    return [qw(args m cmeta handle render wrap main)];
}

method bad_method_names () {
    return [qw(args m cmeta)];
}

method compile () {
    $self->parse();
    return $self->_output_compiled_component();
}

method named_block_types () {
    return [qw(after augment around before filter method override)];
}

method output_class_footer () {
    return "";
}

method output_class_header () {
    return $self->interp->class_header;
}

method parse () {

    # We need to untaint the component source or else the regexes may fail.
    #
    ( $self->{source} ) = ( ( delete $self->{source} ) =~ /(.*)/s )
      if taint_is_on();

    if ( $self->{is_pure_perl} ) {
        $self->{source} = "<%class> " . $self->{source} . " </%class>";
        delete( $self->{methods}->{main} );
    }

    my $lm   = '';
    my $iter = 0;
    while (1) {
        $self->_throw_syntax_error("parse loop iterated >1000 times - infinite loop?")
          if ++$iter > 1000;
        $self->{last_match} = $lm;
        $self->_match_end              && last;
        $self->_match_apply_filter_end && last;
        $self->_match_unnamed_block    && ( $lm = 'unnamed_block' ) && next;
        $self->_match_named_block      && ( $lm = 'named_block' ) && next;
        $self->_match_unknown_block    && ( $lm = 'unknown_block' ) && next;
        $self->_match_apply_filter     && ( $lm = 'apply_filter' ) && next;
        $self->_match_substitution     && ( $lm = 'substitution' ) && next;
        $self->_match_component_call   && ( $lm = 'component_call' ) && next;
        $self->_match_perl_line        && ( $lm = 'perl_line' ) && next;
        $self->_match_bad_close_tag    && ( $lm = 'bad_close_tag' ) && next;
        $self->_match_plain_text       && ( $lm = 'plain_text' ) && next;

        $self->_throw_syntax_error(
            "could not parse next element at position " . pos( $self->{source} ) );
    }
}

method process_perl_code ($coderef) {
    return $coderef;
}

method unnamed_block_types () {
    return [qw(args class doc flags init perl shared text)];
}

method valid_flags () {
    return [qw(extends)];
}

#
# PRIVATE METHODS
#

method _add_to_class_block ($text) {

    # Don't add a line number comment when following a perl-line.
    # We know a perl-line is always _one_ line, so we know that the
    # line numbers are going to match up as long as the first line in
    # a series has a line number comment before it.  Adding a comment
    # can break certain constructs like qw() list that spans multiple
    # perl-lines.
    if ( $self->{last_match} ne 'perl_line' ) {
        $text = $self->_output_line_number_comment . $text;
    }
    $self->{blocks}->{class} .= $text;
}

method _add_to_current_method ($text) {
    if ( $self->{last_match} ne 'perl_line' ) {
        $text = $self->_output_line_number_comment . $text;
    }

    $self->{current_method}->{body} .= $text;
}

method _assert_not_nested ($block_type) {
    $self->_throw_syntax_error(
        "Cannot nest <%$block_type> block inside <%$self->{in_recursive_parse}> block")
      if $self->{in_recursive_parse};
}

method _attribute_declaration ($name, $params, $line_number) {
    $self->_throw_syntax_error("'$name' is reserved and cannot be used as an attribute name")
      if $self->bad_attribute_hash->{$name};
    return $self->_processed_perl_code(
        sprintf(
            "%shas '%s' => %s",
            $self->_output_line_number_comment($line_number),
            $name, $params
        )
    );
}

method _handle_after_block ()    { $self->_handle_method_modifier_block( 'after',    @_ ) }
method _handle_around_block ()   { $self->_handle_method_modifier_block( 'around',   @_ ) }
method _handle_augment_block ()  { $self->_handle_method_modifier_block( 'augment',  @_ ) }
method _handle_before_block ()   { $self->_handle_method_modifier_block( 'before',   @_ ) }
method _handle_override_block () { $self->_handle_method_modifier_block( 'override', @_ ) }

method _handle_method_modifier_block ( $block_type, $contents, $name ) {
    my $modifier = $block_type;

    $self->_throw_syntax_error("Invalid method modifier name '$name'")
      if $name !~ /^$identifier$/;

    $self->_assert_not_nested($block_type);

    my $method_key = "$block_type $name";

    $self->_throw_syntax_error("Duplicate definition of method modifier '$method_key'")
      if exists $self->{methods}->{"$method_key"};

    my $method =
      $self->_new_method_hash( name => $name, type => 'modifier', modifier => $modifier );
    $self->{methods}->{"$method_key"} = $method;

    $self->_recursive_parse( $block_type, $contents, $method );
}

method _handle_apply_filter ($filter_expr) {
    my $rest = substr( $self->{source}, pos( $self->{source} ) );
    my $method = $self->_new_method_hash( type => 'apply_filter' );
    local $self->{end_parse} = undef;
    $self->_recursive_parse( 'filter', $rest, $method );
    if ( my $incr = $self->{end_parse} ) {
        pos( $self->{source} ) += $incr;
    }
    else {
        $self->_throw_syntax_error("'{{' without matching '}}'");
    }
    my $code = sprintf(
        "\$self->m->_apply_filters_to_output(%s, %s);\n",
        $self->_processed_perl_code($filter_expr),
        $self->_output_method($method)
    );
    $self->_add_to_current_method($code);
}

method _handle_args_block ($contents) {
    $self->_handle_attributes_list( $contents, 'args' );
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
                          ^
                          \s*               # optional whitespace
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
                $params = '();';
            }
            if ( $attr_type eq 'shared' ) {
                $params = '(' . 'init_arg => undef, ' . substr( $params, 1 );
            }
            push( @attributes, $self->_attribute_declaration( $name, $params, $line_number ) );
        }
        else {
            $self->{line_number} = $line_number;
            $self->_throw_syntax_error("Invalid attribute line '$line'");
        }
    }
    $self->{blocks}->{attributes} .= join( "\n", @attributes ) . "\n";
}

method _handle_class_block ($contents) {
    $self->{blocks}->{class} .=
      $self->_output_line_number_comment . $self->_processed_perl_code($contents);
}

method _handle_component_call ($contents) {
    my ( $prespace, $call, $postspace ) = ( $contents =~ /(\s*)(.*)(\s*)/s );
    if ( $call =~ m,^[\w/.], ) {
        my $comma = index( $call, ',' );
        $comma = length $call if $comma == -1;
        ( my $comp = substr( $call, 0, $comma ) ) =~ s/\s+$//;
        $call = "'$comp'" . substr( $call, $comma );
    }
    $call = $self->_processed_perl_code($call);
    my $code = "\$m->comp( $prespace $call $postspace \n); ";

    $self->_add_to_current_method($code);
}

method _handle_doc_block () {

    # Don't do anything - just discard the comment.
}

method _handle_filter_block ($contents, $name, $arglist) {
    my $new_contents = join( '',
        '<%perl>',
        'return Mason::DynamicFilter->new(',
        'filter => sub {',
        'my $yield = shift;',
        '$m->capture(sub {',
        '</%perl>', $contents, '<%perl>}); });</%perl>',
    );
    $self->_handle_method_block( $new_contents, $name, $arglist );
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
            if ( $self->valid_flags_hash->{$flag} ) {
                $self->{blocks}->{flags}->{$flag} = eval($value);
                die $@ if $@;
            }
            else {
                $self->_throw_syntax_error("Invalid flag '$flag'");
            }
        }
    }
}

method _handle_init_block ($contents) {
    $self->{current_method}->{init} =
      $self->_output_line_number_comment . $self->_processed_perl_code($contents);
}

method _handle_method_block ( $contents, $name, $arglist ) {
    $self->_throw_syntax_error("Invalid method name '$name'")
      if $name !~ /^$identifier$/;

    $self->_throw_syntax_error("'$name' is reserved and cannot be used as a method name")
      if $self->bad_method_hash->{$name};

    $self->_throw_syntax_error("Duplicate definition of method '$name'")
      if exists $self->{methods}->{$name};

    $self->_assert_not_nested('method');

    my $method = $self->_new_method_hash( name => $name, arglist => $arglist );
    $self->{methods}->{$name} = $method;

    $self->_recursive_parse( 'method', $contents, $method );
}

method _handle_perl_block ($contents) {
    $self->_add_to_current_method( $self->_processed_perl_code($contents) );
}

method _handle_perl_line ($type, $contents) {
    my $code = $self->_processed_perl_code( $contents . "\n" );

    if ( $type eq 'perl' ) {
        $self->_add_to_current_method($code);
    }
    else {
        $self->_add_to_class_block($code);
    }
}

method _handle_plain_text ($text) {

    # Escape single quotes and backslashes
    #
    $text =~ s,([\'\\]),\\$1,g;

    my $code = "\$\$_m_buffer .= '$text';\n";
    $self->_add_to_current_method($code);
}

method _handle_shared_block ($contents) {
    $self->_handle_attributes_list( $contents, 'shared' );
}

method _handle_substitution ( $text, $filter_list ) {

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
        return;
    }

    $text = $self->_processed_perl_code($text);

    if ($filter_list) {
        if ( my @filters = grep { /\S/ } split( /\s*,\s*/, $filter_list ) ) {
            my $filter_call_list = join( ", ", map { "\$self->$_()" } @filters );
            $text =
              sprintf( '$self->m->_apply_filters(%s, sub { local $_ = %s; defined($_) ? $_ : "" })',
                $filter_call_list, $text );
        }
    }

    my $code = "for (scalar($text)) { \$\$_m_buffer .= \$_ if defined }\n";

    $self->_add_to_current_method($code);
}

method _handle_text_block ($contents) {
    $contents =~ s/^\n//;
    $contents =~ s,([\'\\]),\\$1,g;

    $self->_add_to_current_method("\$\$_m_buffer .= '$contents';\n");
}

method _match_apply_filter () {
    my $pos = pos( $self->{source} );

    # Match % ... {{ at beginning of line
    if ( $self->{source} =~ / \G (?<=^) % ([^\n]*) \{\{ [^\S\n]* (?:\#.*)? \n /gcmx ) {
        my ($filter_expr) = ($1);
        $self->_handle_apply_filter($filter_expr);
        return 1;
    }

    # Old syntax, for backward compatibility
    # Match <% ... { %>
    if ( $self->{source} =~ /\G(\n)? <% (.+?) (\s*\{\s*) %>(\n)?/xcgs ) {
        my ( $preceding_newline, $filter_expr, $opening_brace, $following_newline ) =
          ( $1, $2, $3, $4 );

        # and make sure we didn't go through a %>
        if ( $filter_expr !~ /%>/ ) {
            for ( $preceding_newline, $filter_expr, $following_newline ) {
                $self->{line_number} += tr/\n// if defined($_);
            }
            $self->_handle_apply_filter($filter_expr);

            return 1;
        }
        else {
            pos( $self->{source} ) = $pos;
        }
    }

    return 0;
}

method _match_apply_filter_end () {
    if ( $self->{source} =~ / \G (?<=^) % [ \t]+ \}\} [^\S\n]* (?:\#.*)? (?:\n\n?|\z) /gmcx ) {
        if ( $self->{current_method}->{type} eq 'apply_filter' ) {
            $self->{end_parse} = pos( $self->{source} );
            return 1;
        }
        else {
            $self->_throw_syntax_error("'}}' without matching '{{'");
        }
    }

    # Old syntax - <% } %> and </%> - for backward compatibility
    if (   $self->{current_method}->{type} eq 'apply_filter'
        && $self->{source} =~ /\G (?: (?: <% [ \t]* \} [ \t]* %> ) | (?: <\/%> ) ) (\n?\n?)/gcx )
    {
        $self->{end_parse} = pos( $self->{source} );
        return 1;
    }

    return 0;
}

method _match_block ($block_regex, $named) {
    my $regex = qr/
               \G(\n?)
               <% ($block_regex)
               (?: \s+ ([^\s\(>]+) ([^>]*) )?
               >
    /x;
    if ( $self->{source} =~ /$regex/gcs ) {
        my ( $preceding_newline, $block_type, $name, $arglist ) = ( $1, $2, $3, $4 );

        $self->_throw_syntax_error("<%$block_type> block requires a name")
          if ( $named && !defined($name) );

        $self->_throw_syntax_error("<%$block_type> block does not take a name")
          if ( !$named && defined($name) );

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
        $self->_throw_syntax_error("<%$block_type> without matching </%$block_type>");
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
            $self->_throw_syntax_error("'<&' without matching '&>'");
        }
    }
}

method _match_end () {
    if ( $self->{source} =~ /(\G\z)/gcs ) {
        $self->{line_number} += $1 =~ tr/\n//;
        return defined $1 && length $1 ? $1 : 1;
    }
    return 0;
}

method _match_named_block () {
    $self->_match_block( $self->named_block_regex, 1 );
}

method _match_perl_line () {
    if ( $self->{source} =~ /\G(?<=^)(%%?)([^\n]*)(?:\n|\z)/gcm ) {
        my ( $percents, $line ) = ( $1, $2 );
        if ( length($line) && $line !~ /^\s/ ) {
            $self->_throw_syntax_error("$percents must be followed by whitespace or EOL");
        }
        if ( $percents eq '%%' ) {
            if ( $line =~ /\{\s*$/ && $self->{source} =~ /\G(?!%%)/gcm ) {
                $self->_throw_syntax_error("%%-lines cannot be used to surround content");
            }
        }
        $self->_handle_perl_line( ( $percents eq '%' ? 'perl' : 'class' ), $line );
        $self->{line_number}++;

        return 1;
    }
    return 0;
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
                                 (?=[%&]>)    # an end substitution or component call
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

method _match_substitution () {

    return 0 unless $self->{source} =~ /\G<%/gcs;

    if (
        $self->{source} =~ m{
           \G
           (\s*)                # Initial whitespace
           (.+?)                # Substitution body ($1)
           (
            \s*
            (?<!\|)             # Not preceded by a '|'
            \|                  # A '|'
            \s*
            (                   # (Start $3)
             $identifier            # A filter name
             (?:\s*,\s*$identifier)*  # More filter names, with comma separators
            )
           )?
           (\s*)                # Final whitespace
           %>                   # Closing tag
          }xcigs
      )
    {
        my ( $start_ws, $body, $after_body, $filters, $end_ws ) = ( $1, $2, $3, $4, $5 );
        $self->_throw_syntax_error("whitespace required after '<%'") unless length($start_ws);
        $self->{line_number} += tr/\n//
          foreach grep defined, ( $start_ws, $body, $after_body, $end_ws );
        $self->_throw_syntax_error("whitespace required before '%>'") unless length($end_ws);

        $self->_handle_substitution( $body, $filters );

        return 1;
    }
    else {
        $self->_throw_syntax_error("'<%' without matching '%>'");
    }
}

method _match_unknown_block () {
    if ( $self->{source} =~ /\G(?:\n?)<%([A-Za-z_]+)>/gc ) {
        $self->_throw_syntax_error("unknown block '<%$1>'");
    }
}

method _match_unnamed_block () {
    $self->_match_block( $self->unnamed_block_regex, 0 );
}

method _match_bad_close_tag () {
    if ( my ($end_tag) = ( $self->{source} =~ /\G\s*(%>|&>)/gc ) ) {
        ( my $begin_tag = reverse($end_tag) ) =~ s/>/</;
        $self->_throw_syntax_error("'$end_tag' without matching '$begin_tag'");
    }
}

method _new_method_hash () {
    return { body => '', init => '', type => 'method', @_ };
}

method _output_attributes () {
    return $self->{blocks}->{attributes} || '';
}

method _output_class_block () {
    return $self->{blocks}->{class} || '';
}

method _output_class_initialization () {
    return join(
        "\n",
        "our (\$_class_cmeta, \$m, \$_m_buffer, \$_interp);",
        "BEGIN { ",
        "local \$_interp = Mason::Interp->current_load_interp;",
        "\$_interp->component_moose_class->import;",
        "\$_interp->component_import_class->import;",
        "}",
        "*m = \\\$Mason::Request::current_request;",
        "*_m_buffer = \\\$Mason::Request::current_buffer;",

        # Must be defined here since inner relies on caller()
        "sub _inner { inner() }"
    );
}

method _output_cmeta () {
    my $q = sub { "'$_[0]'" };
    my %cmeta_info = (
        dir_path     => $q->( $self->dir_path ),
        is_top_level => $q->( $self->interp->is_top_level_comp_path( $self->path ) ),
        path         => $q->( $self->path ),
        source_file  => $q->( $self->source_file ),
        object_file  => '__FILE__',
        class        => 'CLASS',
        interp       => '$interp',
    );
    return join(
        "\n",
        "method _set_class_cmeta (\$interp) {",
        "\$_class_cmeta = \$interp->component_class_meta_class->new(",
        (
            map { sprintf( "'%s' => %s,", $_, $cmeta_info{$_} ) }
            sort( keys(%cmeta_info) )
        ),
        ');', '}',
        'sub _unset_class_cmeta { undef $_class_cmeta }',
        'sub _class_cmeta { $_class_cmeta }'
    );
}

method _output_compiled_component () {
    return join(
        "\n",
        map { trim($_) } grep { defined($_) && length($_) } (
            $self->_output_flag_comment, $self->_output_class_initialization,
            $self->output_class_header,  $self->_output_global_declarations,
            $self->_output_cmeta,        $self->_output_attributes,
            $self->_output_class_block,  $self->_output_methods,
            $self->output_class_footer,
        )
    ) . "\n";
}

method _output_flag_comment () {
    if ( my $flags = $self->{blocks}->{flags} ) {
        if (%$flags) {
            ( my $json = json_encode($flags) ) =~ s/\n//g;
            return "# FLAGS: $json\n\n";
        }
    }
}

method _output_global_declaration ($spec) {
    my ( $sigil, $name ) = $self->interp->_parse_global_spec($spec);
    return sprintf( 'our %s%s; *%s = \%s%s::%s;' . "\n",
        $sigil, $name, $name, $sigil, $self->interp->globals_package, $name );
}

method _output_global_declarations () {
    return
      join( "\n", map { $self->_output_global_declaration($_) } @{ $self->interp->allow_globals } );
}

method _output_line_number_comment ($line_number) {
    if ( !$self->interp->no_source_line_numbers ) {
        $line_number ||= $self->{line_number};
        if ($line_number) {
            my $comment = sprintf( qq{#line %s "%s"\n}, $line_number, $self->source_file );
            return $comment;
        }
    }
    return "";
}

method _output_method ($method) {
    my $path = $self->path;

    my $name     = $method->{name};
    my $type     = $method->{type};
    my $modifier = $method->{modifier} || '';
    my $arglist  = $method->{arglist} || '';
    my $contents = join( "\n", grep { /\S/ } ( $method->{init}, $method->{body} ) );

    my $start =
        $type eq 'apply_filter' ? "sub {"
      : $modifier eq 'around'   ? "around '$name' => sub {\nmy \$orig = shift; my \$self = shift;"
      : $type     eq 'modifier' ? "$modifier '$name' => sub {\nmy \$self = shift;"
      :                           "method $name $arglist {";
    my $end = $modifier ? "};" : "}";

    return join(
        "\n",
        $start,

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

method _output_methods () {

    # Sort methods so that modifiers come after
    #
    my @sorted_methods_keys =
      sort { ( index( $a, ' ' ) <=> index( $b, ' ' ) ) || $a cmp $b } keys( %{ $self->{methods} } );
    return
      join( "\n", map { $self->_output_method( $self->{methods}->{$_} ) } @sorted_methods_keys );
}

method _processed_perl_code ($code) {
    my $coderef = \$code;
    $self->process_perl_code($coderef);
    return $$coderef;
}

method _recursive_parse ($block_type, $contents, $method) {

    # Save current regex position, then locally set source to the contents and
    # recursively parse.
    #
    local $self->{in_recursive_parse} = $block_type;

    my $save_pos = pos( $self->{source} );
    scope_guard { pos( $self->{source} ) = $save_pos };
    {
        local $self->{source}         = $contents;
        local $self->{current_method} = $method;
        local $self->{line_number}    = $self->{line_number};
        $self->parse();
    }
}

method _throw_syntax_error ($msg) {
    die sprintf( "%s at %s line %d\n", $msg, $self->source_file, $self->{line_number} );
}

__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

Mason::Compilation - Performs compilation of a single component

=head1 DESCRIPTION

A new C<Mason::Compilation> object is created by L<Mason::Interp> to compile
each component.

This class has no public API at this time.

=head1 MODIFIABLE METHODS

These methods are not intended to be called externally, but may be useful to
modify with method modifiers in L<plugins|Mason::Manual::Plugins> and
L<subclasses|Mason::Manual::Subclasses>. Their APIs will be kept as stable as
possible.

=over

=item bad_attribute_names ()

A list of attribute names that should not be used because they are reserved for
built-in attributes or methods: C<args>, C<m>, C<cmeta>, C<render>, C<main>,
etc.

=item bad_method_names ()

A list of method names that should not be used because they are reserved for
built-in attributes: C<args>, C<m>, C<cmeta>, etc. Not as extensive as
bad_attribute_names above because methods like C<render> and C<main> can be
overridden but make no sense as attributes.

=item compile ()

The top-level method called to compile the component. Returns the generated
component class.

=item named_block_types ()

An arrayref of valid named block types: C<after>, C<filter>, C<method>, etc.
Add to this list if you want to create your own named blocks (i.e. blocks that
take a name argument).

=item output_class_footer ()

Perl code to be added at the bottom of the class. Empty by default.

=item output_class_header ()

Perl code to be added at the top of the class, just after initialization of
Moose, C<$m> and other required pieces. The default is the value of Mason::Interp::class_header
or an empty string.

    # Add to the top of every component class:
    #   use Foo;
    #   use Bar qw(baz);
    #
    override 'output_class_header' => sub {
        return join("\n", super(), 'use Foo;', 'use Bar qw(baz);');
    };

=item process_perl_code ($coderef)

This method is called on each distinct piece of Perl code in the component.
I<$coderef> is a reference to a string containing the code; the method can
modify the code as desired. See L<Mason::Plugin::DollarDot> for a sample usage.

=item unnamed_block_types ()

An arrayref of valid unnamed block types: C<args>, C<class>, C<init>, etc. Add
to this list if you want to create your own unnamed blocks.

=item valid_flags ()

An arrayref of valid flags: contains only C<extends> at time of writing. Add to
this list if you want to create your own flags.

=back
