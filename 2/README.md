# Marky the Markdownifier API v2

Endpoint: `https://heckyesmarkdown.com/api/2/`

*(`heckyesmarkdown.com` and `fuckyeahmarkdown.com` are mirrors, you can use either endpoint.)*

Parameters:

Parameters are passed as a query string to the API.


Parameter keys can be shortened to just the first letter (or letters required to be unique). Use 1 for true and 0 for false (also accepts 'true' and 'false').

*The `url` paramter is required, all other parameters are optional (see default values).*

Example:

    curl 'https://heckyesmarkdown.com/api/2/?u=https://brettterpstra.com&read=0`


| Parameter     |  Default   | Description                                     |
| :------------ | :--------: | :---------------------------------------------- |
| `url`         | *required* | Target url to markdownify                       |
| `format`      |   'gfm'    | See [Valid formats](#markup-formats).           |
| `output`      | 'markdown' | [Output format](#output-formats)                |
| `readability` |   false    | Use Readability to remove cruft                 |
| `json`        |   false    | Output JSON { output, html, url, title }        |
| `link`        |   false    | App-specific url. [Link Formats](#link-formats) |
| `open`        |   false    | open link automatically.                        |
| `style`       |    none    | [CSS style](#styles) (HTML output)              |
| `import_css`  |   false    | Embed CSS from linked stylesheets               |
| `complete`    |   false    | output complete HTML page with head/body tags   |

#### Output Formats

The `output` key differs from the `format` key. While `format` determines to what markup the HTML is converted, the `output` key determines how the results will be delivered.

| Value      | Result                                  |
| `--------` | A-------------------------------------e |
| `html`     | An HTML snippet                         |
| `markdown` | Raw converted results based on `format` |
| `url`      | URL encoded version of `format`         |

If `json=1` is specified, this key will be overridden.

#### Markup Formats

Pandoc is used for the initial conversion, which is then cleaned by Marky. Pandoc allows many output formats, so you're not limited to just Markdown. You can, for example, output `asciidoc` or a specific flavor of Markdown, such as `commonmark`, `markdown_mmd`, or `markdown_phpextra`. The default is `gfm` (GitHub Flavored Markdown).

Accepted output formats:

- json
- asciidoc
- asciidoctor
- beamer
- biblatex
- bibtex
- chunkedhtml
- commonmark
- commonmark_x
- context
- csljson
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
- ipynb
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
- opml
- opendocument
- org
- pdf
- plain
- pptx
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

JSON output, either through the `format` parameter or with `json=` in the URL, will output a blob containing `url` (the original URL), `markdown` (which is the output of whatever format is specified), `content` (the rendered HTML version of the output), and `title` (the extracted title of the document).

#### Link Formats

If the `link` parameter is given, output will be url encoded and turned into a link that will operate (on Mac) on specific apps.

| Value        | Result                                                         |
| ------------ | -------------------------------------------------------------- |
| `url`        | Raw encoded url, no protocol                                   |
| `obsidian`   | `obsidian://create` link ([Osidian](https://www.osidian.ca/))  |
| `nv`/`nvalt` | `nv(alt)://make` url (Notational Velocity/nvALT)               |
| `nvultra`    | `x-nvultra://make` url ([nvUltra](https://nvultra.com))        |
| `marked`     | `x-marked://preview` link ([Marked 2](https://marked2app.com)) |

If `open=1` is included in the URL, the generated link will be opened automatically. This will have the effect of creating a new note in the application of choice, or previewing the result (in the case of `marked`). If the result is small, a redirect header will be sent. If it's larger than 8k, it uses a Javascript redirect, requiring a browser window.

#### Styles

[Marked](https://marked2app.com) styles can be added by name in the `style` parameter. Including a style automatically forces `complete` output as HTML with head and body tags. Marked styles include:

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

If you specify a URL in the `style` parameter, the `<link re="stylesheet">` tags from the specified URL will be added to the HTML output of the result. This can have odd effects as most sites style tags and classes that won't exist in the clean output from Marky, but sometimes offers decent styling.

If the `import_css` option is true, then the linked stylesheets will be pulled in and their contents embedded, as well as any `<style>` tags in the target URL. This can be a slow process and often takes multiple seconds to complete.

#### Special handling

Marky has special handling for some sites:

| Site                        | Functionality                                                    |
| --------------------------- | ---------------------------------------------------------------- |
| StackOverflow/StackExchange | Questions, comments, and answers, "accepted" answers highlighted |
| GitHub                      | Outputs just the README contents for the repo                    |

More to come as needs arise.
