const ajax = (options) => {
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
};

const addStyle = (() => {
  const style = document.createElement("style");
  document.head.append(style);
  return (styleString) => (style.textContent = styleString);
})();

const css = `
  #markycontent {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    position: fixed;
    top: 10%;
    z-index: 10000;
    border: solid 1px #ccc;
    border-radius: 8px;
    background: #eee;
    padding: 10px;
    box-shadow: 0 0 10px rgba(0, 0, 0, 0.25);
    width: 80%;
    left: 45%;
    margin-left: -35%;
    height: 100%;
    max-height: 70vh;
    overflow: scroll;
  }

  #markycontent pre {
    background: #fff;
    padding: 20px;
    word-break: break-all;
    text-wrap: wrap;
    max-height: 90%;
  }

  #markycontent .notelink {
    display: block;
    text-align: center;
  }

  #markycontent .notelink a {
    color: #fff;
    background: rgba(255, 178, 0, 0.5);
    font-size: 21px;
    padding: 20px;
    text-decoration: none;
    display: block;
    text-align: center;
    width: 100%;
    transition: background .2s linear;
  }

  #markycontent .notelink a:hover,
  #markycontent .notelink a:focus {
    color: #fff;
    background: rgba(29, 168, 182, 0.5);
    transition: background .2s linear;
  }

  #markycontent button {
    position: fixed;
    padding: 5px 10px;
    background: rgb(156, 32, 46);
    color: #fff;
    font-weight: 600;
    border-radius: 8px;
    opacity: 0.7;
    transition: opacity .2s linear;
  }

  #markycontent button:hover,
  #markycontent button:focus {
    opacity: 1;
    transition: opacity .2s linear;
  }
`;

const reload = () => {
  location.reload();
};

ajax({
  url: `https://fuckyeahmarkdown.com/api/2/?u=${encodeURIComponent(
    window.location.href
  )}&link=nvultra&json=1`,
  method: "get",
}).then((data) => {
  const content = data["markup"];
  const link = data["link"];

  let md = document.createElement("div");
  md.id = "markycontent";
  md.innerHTML = `<button onclick="reload()">X</button><pre><code>${content}</code></pre><p class="notelink"><a href="${link}">Add to nvUltra</a></p>`;

  document.body.appendChild(md);
  addStyle(css);
});
