#!/usr/bin/env python3
"""
UTF-8 aware HTTP server with server-side Markdown rendering.

- .md files are rendered to HTML (GitHub-style) using markdown-it-py
- Append ?raw to any .md URL to view the raw text
- All text files served with charset=utf-8

Usage:
    python3 scripts/serve.py [port] [--bind address] [--directory dir]

Default: port 18999, bind 0.0.0.0, directory .
"""

import http.server
import argparse
import os
import urllib.parse
from markdown_it import MarkdownIt

_md = MarkdownIt().enable("table")

_UTF8_TYPES = {
    ".txt":  "text/plain; charset=utf-8",
    ".log":  "text/plain; charset=utf-8",
    ".csv":  "text/plain; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".html": "text/html; charset=utf-8",
    ".htm":  "text/html; charset=utf-8",
    ".xml":  "application/xml; charset=utf-8",
    ".yaml": "text/plain; charset=utf-8",
    ".yml":  "text/plain; charset=utf-8",
    ".toml": "text/plain; charset=utf-8",
    ".ini":  "text/plain; charset=utf-8",
    ".sh":   "text/plain; charset=utf-8",
    ".py":   "text/plain; charset=utf-8",
}

# Inline GitHub-like CSS — no CDN needed
_CSS = """
*, *::before, *::after { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.6;
  color: #24292f;
  background: #f6f8fa;
  margin: 0;
  padding: 24px 16px;
}
.page-header {
  max-width: 960px;
  margin: 0 auto 12px;
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: #57606a;
}
.page-header a { color: #0969da; text-decoration: none; }
.page-header a:hover { text-decoration: underline; }
.page-header .right { margin-left: auto; }
article {
  max-width: 960px;
  margin: 0 auto;
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  padding: 32px 40px;
}
/* Headings */
h1, h2 { padding-bottom: .3em; border-bottom: 1px solid #d0d7de; }
h1 { font-size: 2em; margin: .67em 0; }
h2 { font-size: 1.5em; }
h3 { font-size: 1.25em; }
/* Tables */
table {
  border-collapse: collapse;
  width: 100%;
  overflow-x: auto;
  display: block;
  margin: 16px 0;
  font-size: 14px;
}
th, td {
  border: 1px solid #d0d7de;
  padding: 6px 13px;
  text-align: left;
}
thead tr { background: #f6f8fa; }
tbody tr:nth-child(even) { background: #f6f8fa; }
/* Code */
code {
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
  font-size: 85%;
  background: #f6f8fa;
  border-radius: 6px;
  padding: .2em .4em;
}
pre {
  background: #f6f8fa;
  border-radius: 6px;
  padding: 16px;
  overflow-x: auto;
  line-height: 1.45;
}
pre code {
  background: transparent;
  padding: 0;
  font-size: 100%;
}
/* Blockquote */
blockquote {
  margin: 0;
  padding: 0 1em;
  color: #57606a;
  border-left: .25em solid #d0d7de;
}
/* Images */
img { max-width: 100%; height: auto; }
/* Links */
a { color: #0969da; }
/* HR */
hr { border: 0; border-top: 1px solid #d0d7de; margin: 24px 0; }
/* Lists */
ul, ol { padding-left: 2em; }
li { margin: .25em 0; }
/* Task list */
input[type=checkbox] { margin-right: 4px; }
@media (max-width: 600px) {
  article { padding: 16px; }
}
"""

_HTML_TEMPLATE = """\
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <style>{css}</style>
</head>
<body>
  <div class="page-header">
    <a href="{parent_url}">&larr; 返回上级目录</a>
    &nbsp;/&nbsp;
    <strong>{title}</strong>
    <span class="right"><a href="{raw_url}">查看原始文本</a></span>
  </div>
  <article>
{body}
  </article>
</body>
</html>
"""


class MarkdownHandler(http.server.SimpleHTTPRequestHandler):

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)
        is_raw = "raw" in query

        if path.lower().endswith(".md") and not is_raw:
            self._serve_markdown(path)
        else:
            super().do_GET()

    def _serve_markdown(self, url_path):
        fs_path = self.translate_path(url_path)
        try:
            with open(fs_path, "r", encoding="utf-8") as f:
                content = f.read()
        except FileNotFoundError:
            self.send_error(404, "File not found")
            return
        except Exception as e:
            self.send_error(500, str(e))
            return

        title = os.path.basename(fs_path)
        parent = url_path.rsplit("/", 1)[0] or "/"
        raw_url = url_path + "?raw=1"

        body_html = _md.render(content)
        html = _HTML_TEMPLATE.format(
            title=title,
            parent_url=parent,
            raw_url=raw_url,
            body=body_html,
            css=_CSS,
        )
        data = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def guess_type(self, path):
        _, ext = os.path.splitext(path)
        if ext.lower() in _UTF8_TYPES:
            return _UTF8_TYPES[ext.lower()]
        return super().guess_type(path)

    def log_message(self, fmt, *args):
        super().log_message(fmt, *args)


def main():
    parser = argparse.ArgumentParser(
        description="UTF-8 static file server with server-side Markdown rendering"
    )
    parser.add_argument("port", type=int, nargs="?", default=18999,
                        help="Port to listen on (default: 18999)")
    parser.add_argument("--bind", "-b", default="0.0.0.0",
                        help="Address to bind to (default: 0.0.0.0)")
    parser.add_argument("--directory", "-d", default=".",
                        help="Directory to serve (default: current directory)")
    args = parser.parse_args()

    handler = lambda *a, **kw: MarkdownHandler(*a, directory=args.directory, **kw)
    with http.server.ThreadingHTTPServer((args.bind, args.port), handler) as httpd:
        print(f"Serving '{args.directory}' at http://{args.bind}:{args.port}")
        print("  .md files rendered as HTML  (append ?raw for plain text)")
        print("Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")


if __name__ == "__main__":
    main()
