function clip() {
  var server = "https://fuckyeahmarkdown.com";
  var nvwin = window.open(
    "",
    "nvwin",
    "status=no,toolbar=no,width=400,height=250,location=no,menubar=no,resizable,scrollbars"
  );
  nvwin.document.title = "Saving";
  nvwin.document.write(`
        <h3>Saving to nvUltra</h3>
        <form action="${server}/api/2/">
        <p>Tags: <input type="text" name="tags" /></p><input type="hidden" name="read" value="1">
        <input type="hidden" name="link" value="nvultra">
        <input type="hidden" name="open" value="1">
        <input type="hidden" name="showframe" value="0">
        <input type="hidden" name="u" value="${encodeURIComponent(
          document.location.href
        )}">
        <p><input type="submit" /></p>
        </form>
        <p><a href="javascript:window.close()">Close</a></p>
        `);
}
