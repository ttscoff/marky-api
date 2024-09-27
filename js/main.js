$(document).ready(function () {
  var $maindiv = $("#maindiv"),
    $previewdiv = $("#previewdiv");

  $.getJSON(
    "/api/2/?url=#{@params[:url]}&readability=#{@params[:readability]}&inline=#{@params[:inline]}&json: 1",
    function (data) {
      var original_markdown = data["markup"],
        refRe = /\[(\d+)\]: (\S+)(?:\s|$)/g,
        matches = original_markdown.match(refRe),
        links = {};

      $(matches).each(function (i, n) {
        n.replace(refRe, function (match, id, url) {
          links[id] = url;
        });
      });
      var markup_markdown = original_markdown
        .replace(/(https?:\/\/\S+)/g, '<a href="$1">$1</a>')
        .replace(/(\[.*?\]\[(\d+)\])/g, function (match, ref, id) {
          return (
            '<a href="javascript:void()" title="' +
            links[id] +
            '" class="reflink">' +
            match +
            "</a>"
          );
        });

      $maindiv.html(markup_markdown);
      $previewdiv.html(data["html"]);

      hljs.highlightBlock($("#maindiv").get(0));
      $(".reflink").tipsy({
        gravity: $.fn.tipsy.autoNS,
        opacity: 1,
        trigger: "manual",
      });
      $("a.reflink, div.tipsy").on("tap", function (ev) {
        ev.preventDefault();
        $(".showing_tipsy").tipsy("hide").removeClass("showing_tipsy");
        if ($(this).hasClass("reflink")) {
          $(this).addClass("showing_tipsy");
          $(this).tipsy("show");
        }
        return false;
      });
      $("a.reflink").on("click", function (ev) {
        ev.preventDefault();
        return false;
      });
      $("#maindiv").on("tap", function (ev) {
        $(".showing_tipsy").tipsy("hide").removeClass("showing_tipsy");
        return true;
      });

      var clipboard = new ClipboardJS(".btn");
      clipboard.on("success", function (e) {
        $("#d_clip_button").html("Copied!");
        setTimeout(function () {
          $("#d_clip_button").html("<?php echo $copytext; ?>");
        }, 2500);

        e.clearSelection();
      });

      clipboard.on("error", function (e) {
        console.error("Action:", e.action);
        console.error("Trigger:", e.trigger);
        $("#d_clip_button").addClass("copyerror").html("Error!");
        setTimeout(function () {
          $("#d_clip_button")
            .removeClass("copyerror")
            .html("<?php echo $copytext; ?>");
        }, 2500);
      });

      // smooth scrolling
      $("a[href^=#]").click(function () {
        if (
          location.pathname.replace(/^\//, "") ==
            this.pathname.replace(/^\//, "") &&
          location.hostname == this.hostname
        ) {
          var $target = $(this.hash);
          $target =
            ($target.length && $target) || $("[id=" + this.hash.slice(1) + "]");
          if ($target.length) {
            var targetOffset = $target.offset().top;
            $("#contentdiv").animate({ scrollTop: targetOffset - 40 }, 1000);
            return false;
          }
        }
      });

      $("#previewbutton").click(function (e) {
        e.preventDefault();
        if ($("#previewdiv").is(":visible")) {
          $("#previewbutton").text("Preview");
          $("#previewdiv")
            .stop(true, true)
            .fadeOut("fast", function () {
              $(this).html("");
              $("#maindiv").stop(true, true).fadeIn();
              $("#d_clip_button").attr("data-clipboard-target", "#maindiv");
            })
            .unbind("click");
        } else {
          $("#maindiv")
            .stop(true, true)
            .fadeOut("fast", function () {
              $("#previewdiv").stop(true, true).html(data).fadeIn("fast");
              $("#previewbutton").text("Close preview");
              $("#d_clip_button").attr("data-clipboard-target", "#previewdiv");
              // widont titles
              $("h1,h2,h3,h4").each(function () {
                $(this).html(
                  $(this)
                    .text()
                    .replace(/([^\s])\s+([^\s]+)\s*$/, "$1&nbsp;$2")
                );
              });
            });
        }
        return false;
      });
      $("#nightmode").click(function () {
        if ($(this).is(":checked")) {
          $("body").addClass("inverted");
          $.cookie("fymdnightmode", 1);
        } else {
          $("body").removeClass("inverted");
          $.cookie("fymdnightmode", 0);
        }
      });
    }
  );
});
