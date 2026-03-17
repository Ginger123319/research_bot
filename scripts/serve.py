#!/usr/bin/env python3
"""
UTF-8 aware HTTP server with server-side Markdown rendering + guofan Dashboard.

Routes:
  GET /                     → guofan model evaluation Dashboard (HTML)
  GET /api/models           → JSON list of all models from INDEX.yaml
  GET /api/models/{name}    → JSON detail for one model
  GET /*.md                 → Markdown rendered as GitHub-style HTML
  GET /*                    → Static file / directory listing

- Append ?raw to any .md URL to view the raw text
- All text files served with charset=utf-8

Usage:
    python3 scripts/serve.py [port] [--bind address] [--directory dir]

Default: port 18999, bind 0.0.0.0, directory .
"""

import http.server
import argparse
import os
import json
import datetime
import urllib.parse
from markdown_it import MarkdownIt

try:
    import yaml
except ImportError:
    raise RuntimeError("pyyaml not installed: run .venv/bin/pip install pyyaml")

_md = MarkdownIt().enable("table")

_PERFORMANCE_KEYS = [
    "sla_max_qps_rps", "sla_max_qps_rpm", "replay_success_rate",
    "replay_ttft_p90_s", "replay_e2e_p90_s",
]

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
/* Dashboard-specific */
.dash-header {
  max-width: 1100px;
  margin: 0 auto 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.dash-header h1 { border: 0; margin: 0; font-size: 1.4em; }
.dash-header a { font-size: 13px; color: #0969da; text-decoration: none; }
.dash-wrap { max-width: 1100px; margin: 0 auto; }
.stat-row {
  display: flex;
  gap: 12px;
  margin-bottom: 20px;
  flex-wrap: wrap;
}
.stat-card {
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  padding: 14px 24px;
  min-width: 130px;
  text-align: center;
}
.stat-card .num { font-size: 2em; font-weight: 600; color: #24292f; }
.stat-card .lbl { font-size: 13px; color: #57606a; margin-top: 2px; }
.stat-card.c-done .num { color: #1a7f37; }
.stat-card.c-prog .num { color: #9a6700; }
.insights-block {
  background: #fff8c5;
  border: 1px solid #d4a72c;
  border-radius: 6px;
  padding: 12px 18px;
  margin-bottom: 20px;
  font-size: 14px;
}
.insights-block .ins-title { font-weight: 600; margin-bottom: 6px; }
.insights-block li { margin: 3px 0; }
.model-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  gap: 16px;
}
.model-card {
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  padding: 18px 20px;
}
.model-card .card-title {
  font-size: 15px;
  font-weight: 600;
  margin-bottom: 6px;
  word-break: break-all;
}
.model-card .card-status { font-size: 13px; margin-bottom: 8px; }
.model-card .card-meta { font-size: 13px; color: #57606a; margin-bottom: 10px; }
.model-card .card-meta span { display: block; }
.model-card .card-actions { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 10px; }
.btn {
  display: inline-block;
  font-size: 12px;
  padding: 4px 12px;
  border-radius: 6px;
  text-decoration: none;
  border: 1px solid #d0d7de;
  background: #f6f8fa;
  color: #24292f;
  cursor: pointer;
}
.btn:hover { background: #e8ebef; }
.btn-primary { background: #0969da; color: #fff; border-color: #0969da; }
.btn-primary:hover { background: #0550ae; }
.exp-list { font-size: 12px; color: #57606a; margin-top: 6px; }
.exp-list a { color: #0969da; text-decoration: none; font-size: 12px; }
.exp-list a:hover { text-decoration: underline; }
.warn-text { color: #9a6700; font-size: 12px; margin: 4px 0; }
.err-box {
  background: #fff8f8;
  border: 1px solid #f85149;
  border-radius: 6px;
  padding: 20px 24px;
  margin: 20px auto;
  max-width: 700px;
}
.ts-note { font-size: 12px; color: #57606a; margin-top: 16px; text-align: right; }
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


def _json_default(obj):
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")


def _normalize_model(model):
    """Ensure performance is always a dict (with null values for in_progress models)."""
    m = dict(model)
    if m.get("performance") is None:
        m["performance"] = {k: None for k in _PERFORMANCE_KEYS}
    return m


def _html_escape(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


class MarkdownHandler(http.server.SimpleHTTPRequestHandler):

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # Dashboard and API routes (checked before static file handling)
        if path in ("/", ""):
            self._serve_dashboard()
            return
        if path == "/api/models":
            self._serve_api_models()
            return
        if path.startswith("/api/models/"):
            raw_name = path[len("/api/models/"):]
            name = urllib.parse.unquote(raw_name.rstrip("/"))
            if not name:
                self._send_json({"error": "model name required"}, status=404)
                return
            self._serve_api_model_detail(name)
            return

        # Original logic
        query = urllib.parse.parse_qs(parsed.query)
        is_raw = "raw" in query
        if path.lower().endswith(".md") and not is_raw:
            self._serve_markdown(path)
        else:
            super().do_GET()

    # ── INDEX.yaml helpers ──────────────────────────────────────────────────

    def _load_index(self):
        """Return (data, None) on success or (None, error_str) on failure."""
        index_path = os.path.join(self.directory, "models", "INDEX.yaml")
        try:
            with open(index_path, "r", encoding="utf-8") as f:
                data = yaml.safe_load(f)
            if not data or "models" not in data:
                return None, "INDEX.yaml is empty or missing 'models' key"
            return data, None
        except FileNotFoundError:
            return None, f"INDEX.yaml not found at {index_path}"
        except yaml.YAMLError as e:
            return None, f"YAML parse error: {e}"
        except Exception as e:
            return None, str(e)

    def _get_index_mtime(self):
        """Return INDEX.yaml mtime as CST ISO string, or None on error."""
        index_path = os.path.join(self.directory, "models", "INDEX.yaml")
        try:
            ts = os.path.getmtime(index_path)
            tz_cst = datetime.timezone(datetime.timedelta(hours=8))
            return datetime.datetime.fromtimestamp(ts, tz=tz_cst).isoformat()
        except Exception:
            return None

    # ── Response helpers ────────────────────────────────────────────────────

    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False, indent=2,
                          default=_json_default).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html, status=200):
        body = html.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ── API routes ──────────────────────────────────────────────────────────

    def _serve_api_models(self):
        data, error = self._load_index()
        if error:
            self._send_json({"error": "index unavailable", "detail": error}, status=503)
            return
        models = [_normalize_model(m) for m in data.get("models", [])]
        statuses = [m.get("eval_status") for m in models]
        summary = {
            "total": len(models),
            "completed": statuses.count("completed"),
            "in_progress": statuses.count("in_progress"),
            "pending": statuses.count("pending"),
            "last_updated": self._get_index_mtime(),
        }
        self._send_json({"summary": summary, "models": models})

    def _serve_api_model_detail(self, name):
        data, error = self._load_index()
        if error:
            self._send_json({"error": "index unavailable", "detail": error}, status=503)
            return
        for m in data.get("models", []):
            if m.get("model_name") == name:
                self._send_json(_normalize_model(m))
                return
        self._send_json({"error": "model not found", "model_name": name}, status=404)

    # ── Dashboard ───────────────────────────────────────────────────────────

    def _exp_link(self, exp_path):
        """Build a clickable URL for a linked_experiments entry."""
        host = self.headers.get("Host", "localhost").split(":")[0]
        if exp_path.startswith("results/"):
            rel = exp_path[len("results/"):]
            report_full = os.path.join(self.directory, rel, "REPORT.md")
            if os.path.exists(report_full):
                return f"/{rel}/REPORT.md"
            return f"/{rel}/"
        elif exp_path.startswith("logs/"):
            rel = exp_path[len("logs/"):]
            return f"http://{host}:8765/{rel}/"
        return f"/{exp_path}/"

    def _render_model_card(self, model):
        name = _html_escape(model.get("model_name", "unknown"))
        status = model.get("eval_status", "unknown")
        model_type = _html_escape(model.get("model_type") or "—")
        dep = model.get("deployment") or {}
        tp = dep.get("tp_size", "?")
        gpu_type = _html_escape(dep.get("gpu_type") or "?")
        gpu_count = dep.get("gpu_count", "?")
        perf = model.get("performance") or {}
        qps = perf.get("sla_max_qps_rps")
        qps_str = f"{qps} req/s" if qps is not None else "—"
        rec = _html_escape(model.get("recommendation") or "")
        completed_date = model.get("eval_completed_date") or ""
        file_warning = model.get("_file_warning", "")

        # Status badge
        if status == "completed":
            status_html = '<span style="color:#1a7f37">✅ 已完成</span>'
            if completed_date:
                status_html += f' <span style="color:#57606a;font-size:12px">{_html_escape(str(completed_date))}</span>'
        elif status == "in_progress":
            status_html = '<span style="color:#9a6700">🔄 评估中</span>'
        else:
            status_html = f'<span style="color:#57606a">{_html_escape(status)}</span>'

        # Action buttons
        actions_html = ""
        eval_report_path = (model.get("paths") or {}).get("eval_report")
        if status == "completed" and eval_report_path:
            rel = eval_report_path[len("results/"):] if eval_report_path.startswith("results/") else eval_report_path
            actions_html += f'<a class="btn btn-primary" href="/{rel}">查看报告</a>'

        # For in_progress: find first logs/ experiment for progress link
        if status == "in_progress":
            for exp in (model.get("linked_experiments") or []):
                if exp.startswith("logs/"):
                    host = self.headers.get("Host", "localhost").split(":")[0]
                    rel = exp[len("logs/"):]
                    actions_html += f'<a class="btn" href="http://{host}:8765/{rel}/progress.txt" target="_blank">查看进度</a>'
                    break

        # Experiment list
        exp_items = ""
        for exp in (model.get("linked_experiments") or []):
            label = exp.replace("results/", "").replace("logs/", "📋 ")
            link = self._exp_link(exp)
            exp_items += f'<div><a href="{_html_escape(link)}" target="_blank">{_html_escape(label)}</a></div>'

        warn_html = f'<p class="warn-text">{_html_escape(file_warning)}</p>' if file_warning else ""

        return f"""
<div class="model-card">
  <div class="card-title">{name}</div>
  <div class="card-status">{status_html}</div>
  <div class="card-meta">
    <span>类型：{model_type}</span>
    <span>部署：{tp}TP × {gpu_type}（共 {gpu_count} 卡）</span>
    <span>拐点：{qps_str}</span>
    {f'<span style="font-size:12px">{rec}</span>' if rec else ''}
  </div>
  {warn_html}
  <div class="card-actions">{actions_html}</div>
  <div class="exp-list">{exp_items}</div>
</div>"""

    def _serve_dashboard(self):
        data, error = self._load_index()

        if error:
            body = f"""
<div class="err-box">
  <h2>⚠️ 数据加载失败</h2>
  <p><strong>错误信息：</strong><code>{_html_escape(error)}</code></p>
  <h3>可能原因：</h3>
  <ul>
    <li><code>results/models/INDEX.yaml</code> 被移动或删除</li>
    <li><code>serve.py</code> 的 <code>--directory</code> 参数配置错误</li>
    <li>INDEX.yaml 格式错误（YAML 语法问题）</li>
  </ul>
  <h3>解决方法：</h3>
  <ol>
    <li>检查 <code>results/models/INDEX.yaml</code> 是否存在</li>
    <li>验证语法：<code>python3 -c "import yaml; yaml.safe_load(open('results/models/INDEX.yaml'))"</code></li>
    <li>查看日志：<code>tail -f logs/data-pipeline/serve_18999.log</code></li>
  </ol>
  <p><a href="/">刷新页面</a></p>
</div>"""
            page = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>guofan Dashboard - 错误</title><style>{_CSS}</style></head>
<body><div class="dash-wrap">{body}</div></body></html>"""
            self._send_html(page)
            return

        models = data.get("models", [])

        # File-existence check for completed models
        for model in models:
            if model.get("eval_status") == "completed":
                rp = (model.get("paths") or {}).get("eval_report")
                if rp and rp.startswith("results/"):
                    rel = rp[len("results/"):]
                    if not os.path.exists(os.path.join(self.directory, rel)):
                        model["_file_warning"] = f"⚠️ {rp} 不存在，报告链接不可用"

        # Summary stats
        statuses = [m.get("eval_status") for m in models]
        n_done = statuses.count("completed")
        n_prog = statuses.count("in_progress")
        n_total = len(models)
        last_updated = self._get_index_mtime() or "—"

        stats_html = f"""
<div class="stat-row">
  <div class="stat-card c-done"><div class="num">{n_done}</div><div class="lbl">已完成</div></div>
  <div class="stat-card c-prog"><div class="num">{n_prog}</div><div class="lbl">进行中</div></div>
  <div class="stat-card"><div class="num">{n_total}</div><div class="lbl">合计</div></div>
</div>"""

        # Insights block (optional)
        insights = data.get("insights") or []
        insights_html = ""
        if insights:
            items = "".join(f"<li>{_html_escape(i)}</li>" for i in insights)
            insights_html = f"""
<div class="insights-block">
  <div class="ins-title">💡 关键发现</div>
  <ul>{items}</ul>
</div>"""

        # Model cards
        cards_html = "\n".join(self._render_model_card(m) for m in models)

        page = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>guofan 模型评估平台</title>
  <style>{_CSS}</style>
</head>
<body>
<div class="dash-wrap">
  <div class="dash-header">
    <h1>🐈 guofan 模型评估平台</h1>
    <a href="javascript:location.reload()">⟳ 刷新</a>
  </div>
  {stats_html}
  {insights_html}
  <div class="model-grid">
    {cards_html}
  </div>
  <p class="ts-note">数据更新时间：{_html_escape(last_updated)}</p>
</div>
</body>
</html>"""
        self._send_html(page)

    # ── Markdown rendering ──────────────────────────────────────────────────

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
        description="UTF-8 static file server with Markdown rendering and guofan Dashboard"
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
        print("  GET /              → guofan Dashboard")
        print("  GET /api/models    → JSON API")
        print("  GET /*.md          → Markdown rendered as HTML  (append ?raw for plain text)")
        print("Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")


if __name__ == "__main__":
    main()
