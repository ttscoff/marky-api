const ajax = ((options) => {
  return new Promise(function (resolve, reject) {
    fetch(options.url, {
      method: options.method,
      headers: options.headers,
      body: options.body,
    })
      .then(function (response) {
        response
          .json()
          .then(function (json) {
            resolve(json);
          })
          .catch((err) => reject(err));
      })
      .catch((err) => reject(err));
  });
})();

const addStyle = (() => {
  const style = document.createElement("style");
  document.head.append(style);
  return (styleString) => (style.textContent = styleString);
})();

const css = `
  #markycontent {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    position: fixed;
    left: 20vw;
    right: 20vw;
    top: 20vw;
    z-index: 100;
    border: solid 1px #ccc;
    border-radius: 8px;
    background: #eee;
    padding: 10px;
    box-shadow: 0 0 10px rgba(0, 0, 0, 0.25);
  }

  .notelink {
  display: block;
  text-align: center;
    padding: 10px;
    background: #fafafa;
  }

  .notelink a {
    color: #0077cc;
    text-decoration: none;
    display: block;
    text-align: center;
  }
`;

ajax({
  url: `https://fuckyeahmarkdown.com/api/2/?u=${window.location.href}&link=nvultra&json=1`,
  method: "get",
}).then((data) => {
  const content = data["markup"];
  const link = data["link"];

  let md = document.createElement("div");
  md.id = "markycontent";
  md.innerHTML = `<p class="notelink"><a href="${link}">Add to nvUltra</a></p><pre><code>${content}</code></pre>`;

  document.body.appendChild(md);
  addStyle(css);
});
