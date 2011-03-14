<%augment wrap>
  <html>
    <head>
      <link rel="stylesheet" href="/static/css/mblog.css">
      <title>My Blog</title>
    </head>
    <body>

% if (my $message = delete($m->req->session->{message})) {
      <div class="message"><% $message %></div>
% }      

      <% inner() %>
    </body>
  </html>
</%augment>
