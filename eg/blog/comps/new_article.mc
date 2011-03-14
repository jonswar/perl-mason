<h2>Add an article</h2>

<% $.FillInForm($form_data) { %>
<form action="/article/publish" method=post>
  <p>Title: <input type=text size=30 name=title></p>
  <p>Text:</p>
  <textarea name=content rows=20 cols=70></textarea>
  <p><input type=submit value="Publish"></p>
</form>
</%>

<%init>
my $form_data = delete($m->req->session->{form_data});
</%init>
