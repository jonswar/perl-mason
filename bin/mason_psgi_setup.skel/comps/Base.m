<%text>
<%shared>
$.title => ''
</%shared>

<%augment wrap>
<html>
  <head>
    <% $.Defer { %>
    <title>My site: <% $.title %></title>
    </%>
  </head>
  <body>
    <% inner() %>
  </body>
</html>
</%augment>
</%text>
