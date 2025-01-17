<script>0</script>

## API v2

- [API v2](#api-v2)
- [Endpoint](#endpoint)
- [Parameters](#parameters)
  - [Output Formats](#output-formats)
  - [Processing HTML](#processing-html)
  - [Readability and conversion](#readability-and-conversion)
    - [Custom Readability](#custom-readability)
    - [Table formatting](#table-formatting)
    - [Code block formatting](#code-block-formatting)
  - [Markup Formats](#markup-formats)
  - [Link Formats](#link-formats)
  - [Styles](#styles)
- [Special handling](#special-handling)
- [Bookmarklet](#bookmarklet)

## Endpoint

    https://heckyesmarkdown.com/api/2/?[query string]


*(`heckyesmarkdown.com` and `fuckyeahmarkdown.com` are mirrors, you can use
either endpoint.)*

## Parameters

Parameters are passed as a query string to the API.


Parameter keys can be shortened to just the first letter (or letters required to
be unique). Use 1 for true and 0 for false (also accepts 'true' and 'false').

*The `url` parameter is required, all other parameters are optional (see default
values).*

Example:

    curl 'https://heckyesmarkdown.com/api/2/?u=https://brettterpstra.com&read=0`


| Parameter     |    Default     | Description                                     |
| :------------ | :------------: | :---------------------------------------------- |
| `url`         |   *required*   | Target url to markdownify                       |
| `complete`    |     false      | Output complete HTML page with head/body tags   |
| `format`      | 'markdown_mmd' | See [Valid formats](#markup-formats).           |
| `inline`      |      true      | Use inline link format                          |
| `import_css`  |     false      | Embed CSS from linked stylesheets               |
| `json`        |     false      | Output JSON { output, html, url, title }        |
| `link`        |     false      | App-specific url. [Link Formats](#link-formats) |
| `open`        |     false      | Open link automatically.                        |
| `output`      |   'markdown'   | [Output format](#output-formats)                |
| `readability` |     false      | Use Readability to remove cruft                 |
| `showframe`   |     false      | Output the Marky results page                   |
| `style`       |      none      | [CSS style](#styles) (HTML output)              |
| `html`        |      none      | If provided, [process HTML](#processing-html)   |
| `title`       |      none      | If provided, use instead of extracting          |

### Output Formats

The `output` key differs from the `format` key. While `format` determines to
what markup the HTML is converted, the `output` key determines how the results
will be delivered.

| Value      | Result                                  |
| :--------- | :-------------------------------------- |
| `complete` | Complete HTML document                  |
| `html`     | An HTML snippet                         |
| `markdown` | Raw converted results based on `format` |
| `url`      | URL encoded version of `format`         |

If `json=1` is specified, this key will be overridden.

### Processing HTML

If the `html` parameter is provided with raw HTML (url encoded), either by
GET or POST, it will use that HTML rather than running
Readability on the `url`. If the `url` paramater is used in
conjunction with `html`, it will be used as the base URL for
any link conversions and as the `source:` keyword for the
document. If a `title` is provided, it will be used as the
title for the document. `url` and `title` are both optional
when processing HTML.

### Readability and conversion

#### Custom Readability

Marky uses a custom version of Arc90's Readability. It's a little more lax and
picks up things like author blocks and occasionally share blocks, but is more
likely to include _all_ the pertinent content on the page. Arc90 gets confused
when the page markup splits the article content into multiple divs and picks
just one. Marky attempts to prevent that. Enable Marky's Readability by
including `readability=1` in the url.

#### Table formatting

Tables are converted to Markdown and formatted nicely. Tables that contain
content that's not valid in Markdown tables (per PHP Extra/MultiMarkdown spec)
will be compressed (lists and line breaks replaced).

#### Code block formatting

Code blocks are converted to backtick-fenced code. When possible, a specified
language is applied after the opening fence.

### Markup Formats

Pandoc is used for the initial conversion, which is then cleaned by Marky.
Pandoc allows many output formats, so you're not limited to just Markdown. You
can, for example, output `asciidoc` or a specific flavor of Markdown, such as
`commonmark`, `markdown_mmd`, or `markdown_phpextra`. The default is `markdown_mmd`
(GitHub Flavored Markdown).

Accepted output formats:

- asciidoc
- asciidoctor
- beamer
- commonmark
- commonmark_x
- context
- docbook
- docbook4
- docbook5
- dokuwiki
- fb2
- gfm
- haddock
- html
- html5
- html4
- icml
- jats_archiving
- jats_articleauthoring
- jats_publishing
- jats
- jira
- latex
- man
- markdown
- markdown_mmd
- markdown_phpextra
- markdown_strict
- markua
- mediawiki
- ms
- muse
- native
- opendocument
- org
- plain
- rst
- rtf
- texinfo
- textile
- slideous
- slidy
- dzslides
- revealjs
- s5
- tei
- xwiki
- zimwiki

JSON output, either through the `format` parameter or with `json=` in the URL,
will output a blob containing `url` (the original URL), `markup` (which is the
output of whatever format is specified), `html` (the rendered HTML version of
the output), and `title` (the extracted title of the document). If a `link=X`
parameter is provided, an additional `link` field will be included with the
encoded link.

Example:

    curl "https://fuckyeahmarkdown.com/go/?u=https://example.com&json=1"

Response:

    {
      "url": "https://example.com",
      "markup": "# Example Title\n\nThis is an example paragraph.",
      "html": "<h1>Example Title</h1>\n<p>This is an example paragraph.</p>",
      "title": "Example Title"
    }

### Link Formats

If the `link` parameter is given, output will be url encoded and turned into a
link that will operate (on Mac) on specific apps.

| Value              | Result                                                                                |
| ------------------ | ------------------------------------------------------------------------------------- |
| `url`              | Raw encoded url, no protocol                                                          |
| `obsidian`         | `obsidian://create` link ([Osidian](https://www.osidian.ca/))                         |
| `nv`/`nvalt`       | `nv(alt)://make` url (Notational Velocity/nvALT)                                      |
| `nvultra`, `nvu`   | `x-nvultra://make` url ([nvUltra](https://nvultra.com))                               |
| `marked`           | `x-marked://preview` link ([Marked 2](https://marked2app.com))                        |
| `devonthink`, `dt` | `x-devonthink://createMarkdown` link [DEVONthink](https://www.devontechnologies.com/) |

If `open=1` is included in the URL, the generated link will be opened
automatically. This will have the effect of creating a new note in the
application of choice, or previewing the result (in the case of `marked`). If
the result is small, a redirect header will be sent. If it's larger than 8k, it
uses a Javascript redirect, requiring a browser window.

Example:

    curl "https://fuckyeahmarkdown.com/go/?u=https://example.com&json=1&link=obsidian"

Response:

    {
      "url": "https://example.com",
      "markup": "# Example Title\n\nThis is an example paragraph.",
      "html": "<h1>Example Title</h1>\n<p>This is an example paragraph.</p>",
      "title": "Example Title",
      "link": "obsidian://create?content=[url encoded content]"
    }

### Styles

[Marked](https://marked2app.com) styles can be added by name in the `style`
parameter. Including a style automatically forces `complete` output as HTML with
head and body tags. Marked styles include:

- amblin
- fountain
- github
- grump
- ink
- lopash
- manuscript
- modern
- swiss
- upstandingcitizen

Example:

    curl 'https://heckyesmarkdown.com/api/2/?u=https://brettterpstra.com&read=1&style=swiss

If you specify a URL in the `style` parameter, the `<link re="stylesheet">` tags
from the specified URL will be added to the HTML output of the result. This can
have odd effects as most sites style tags and classes that won't exist in the
clean output from Marky, but sometimes offers decent styling.

If the `import_css` option is true, then the linked stylesheets will be pulled
in and their contents embedded, as well as any `<style>` tags in the target URL.
This can be a slow process and often takes multiple seconds to complete.

## Special handling

Marky has special handling for some sites:

| Site                   | Functionality                                 |
| ---------------------- | --------------------------------------------- |
| StackOverflow/Exchange | Qs, comments, and As, "accepted" highlighted  |
| GitHub Repo            | Outputs just the README contents for the repo |
| GitHub Gist            | Formats code block with title                 |
| GitHub File            | Formats file code with title                  |

More to come as needs arise.

## Bookmarklet

Open current page in Marky:

```
javascript:(function(){var nvwin = window.open("","nvwin","status=no,toolbar=no,width=400,height=250,location=no,menubar=no,resizable,scrollbars");nvwin.document.title = "Saving";nvwin.window.location = `https://heckyesmarkdown.com/api/2/?link=nvultra&open=1&read=1&u=${encodeURIComponent(document.location.href)}`;})();
```
