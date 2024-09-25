(function () {
  var a = document.createElement("link");
  a.rel = "stylesheet";
  a.href = "//fuckyeahmarkdown.com/api/2/bookmarklets/nvultra.css";
  a.onload = function () {
    var a = b.currentStyle
      ? b.currentStyle.fontFamily
      : document.defaultView.getComputedStyle(b, null).fontFamily;
    eval(a.replace(/^["']|\\|["']$/g, ""));
  };
  document.body.appendChild(a);
  var b = document.createElement("div");
  b.id = "markygo";
  document.body.appendChild(b);
})();
