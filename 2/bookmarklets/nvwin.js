javascript: (function () {
  var nvwin = window.open(
    "",
    "nvwin",
    "status=no,toolbar=no,width=600,height=800,location=no,menubar=no,resizable,scrollbars"
  );
  nvwin.document.title = "Marky";
  nvwin.window.location = `https://fuckyeahmarkdown.com/preview.cgi?read=1&inline=1&u=${encodeURIComponent(
    document.location.href
  )}`;
})();
