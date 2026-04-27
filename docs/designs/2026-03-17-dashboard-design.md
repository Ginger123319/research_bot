# guofan Dashboard 设计文档

**日期**：2026-03-17  
**状态**：草稿，待评审  
**范围**：在现有 `scripts/serve.py` 基础上扩展，为团队提供模型评估总览 Dashboard 和供 openclaw 调用的 JSON API

---

## 一、背景与目标

### 现状

- `scripts/serve.py` 已在运行：
  - 端口 18999：服务 `results/`（Markdown 渲染，可浏览 EVAL_REPORT.md、REPORT.md）
  - 端口 8765：服务 `logs/`（可浏览 progress.txt 等）
- `results/models/INDEX.yaml` 已有结构化模型评估索引（Phase 1 产物）
- openclaw 目前通过读文件（`INDEX.yaml` + `EVAL_REPORT.md`）获取模型状态

### 问题

- 访问 `http://host:18999/` 只显示目录列表，团队无法快速了解"哪些模型已完成、结论是什么"
- openclaw 读本地文件的方式不便于跨环境/跨项目访问，需要 HTTP JSON 接口

### 目标

1. `http://host:18999/` → 模型评估总览 Dashboard（替换原目录列表）
2. `GET /api/models` 和 `GET /api/models/{name}` → JSON API，供 openclaw 调用
3. 零新依赖、不影响现有文件服务行为

---

## 二、不在范围内

- Skill Marketplace / Workflow Builder（独立产品，不属于 guofan）
- 任何"评估效率提升 X%"等无数据支撑的统计展示
- Streamlit / Docker / Nginx / FastAPI（不引入 Web 框架级依赖）
- 数据写入 / 更新接口（只读）
- PDF 导出、飞书分享等

---

## 三、架构

### 扩展方案：在 MarkdownHandler 中新增 3 条路由

```
scripts/serve.py  （仅扩展，不重写）

新增路由：
  GET /              → Dashboard HTML（拦截根路径，替换目录列表）
  GET /api/models    → JSON（读 results/models/INDEX.yaml）
  GET /api/models/*  → JSON（读 INDEX.yaml 指定条目）

原有路由（保持不变）：
  GET /*.md          → Markdown 渲染 HTML
  GET /*             → 静态文件（目录列表 / 文件下载）
```

### 数据来源

```
GET /                            GET /api/models    GET /api/models/{name}
      │                                │                    │
      ▼                                ▼                    ▼
  INDEX.yaml（全部模型）          INDEX.yaml         INDEX.yaml 对应条目
  → 渲染 HTML 卡片墙              → JSON 返回         + 无额外文件读取（详情已在条目内）
```

**INDEX.yaml 是唯一数据源**，Dashboard 展示内容不超出 INDEX.yaml 已有字段，不造假数据。

### 路径前缀处理规则

18999 服务以 `--directory results` 启动，URL `/foo` 映射到磁盘 `results/foo`。因此 INDEX.yaml 中的路径字段（以 `results/` 开头）在构建链接时必须剥离 `results/` 前缀：

```
INDEX.yaml 字段值                                    → 18999 服务 URL
results/models/tianji-.../EVAL_REPORT.md            → /models/tianji-.../EVAL_REPORT.md
results/tianji_querysafety_benchmark_20260312        → /tianji_querysafety_benchmark_20260312/
```

`linked_experiments` 中 `logs/` 开头的条目指向 8765 服务（`--directory logs`），需构建绝对 URL：

```
INDEX.yaml 字段值                                    → 8765 服务 URL
logs/guoxue_8tp_qps_20260316_163202                 → http://host:8765/guoxue_8tp_qps_20260316_163202/
```

**`[查看进度]` 的链接规则**：取 `linked_experiments` 中第一个 `logs/` 前缀条目，拼接 `/progress.txt`，构建为绝对 URL（指向 8765 服务）。若无 `logs/` 条目则不显示该按钮。

---

## 四、API 规范

### `GET /api/models`

返回所有模型列表和汇总统计。

**响应示例**：
```json
{
  "summary": {
    "total": 2,
    "completed": 1,
    "in_progress": 1,
    "pending": 0,
    "last_updated": "2026-03-17T14:16:00+08:00"
  },
  "models": [
    {
      "model_name": "tianji-querysafety-4b-v2-3",
      "model_type": "安全拦截模型",
      "eval_status": "completed",
      "eval_completed_date": "2026-03-16",
      "deployment": {
        "tp_size": 4,
        "gpu_type": "L20",
        "gpu_count": 4
      },
      "performance": {
        "sla_max_qps_rps": 8.0,
        "sla_max_qps_rpm": 480,
        "replay_success_rate": 100.0,
        "replay_ttft_p90_s": 0.148,
        "replay_e2e_p90_s": 0.236
      },
      "recommendation": "✅ 可上线，推荐 6 实例 × 4TP（共 24 卡 L20）",
      "paths": {
        "model_context": "results/models/tianji-querysafety-4b-v2-3/model-context.md",
        "eval_report": "results/models/tianji-querysafety-4b-v2-3/EVAL_REPORT.md"
      },
      "linked_experiments": [
        "results/tianji_querysafety_benchmark_20260312",
        "results/tianji_querysafety_4tp_fullrange_20260313",
        "results/tianji_querysafety_4tp_vs_4dp_filtered_20260313"
      ]
    },
    {
      "model_name": "xinghan-guoxue-72b-v1-2-reason",
      "model_type": "推理对话模型",
      "eval_status": "in_progress",
      "eval_completed_date": null,
      "deployment": {
        "tp_size": 8,
        "gpu_type": "H100",
        "gpu_count": 8
      },
      "performance": {
        "sla_max_qps_rps": null,
        "sla_max_qps_rpm": null,
        "replay_success_rate": null,
        "replay_ttft_p90_s": null,
        "replay_e2e_p90_s": null
      },
      "recommendation": null,
      "paths": {
        "model_context": "results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md",
        "eval_report": null
      },
      "linked_experiments": [
        "results/guoxue_partial_20260317",
        "logs/guoxue_8tp_qps_20260316_163202"
      ]
    }
  ]
}
```

### `GET /api/models/{name}`

返回单个模型的完整 INDEX.yaml 条目（结构同上单条）。

**404 响应**（HTTP 404）：
```json
{"error": "model not found", "model_name": "xxx"}
```

**503 响应**（INDEX.yaml 不可用时）：
```json
{"error": "index unavailable", "detail": "<错误描述>"}
```

### 路由匹配规则

```python
# 路由优先级（在 do_GET 开头按顺序判断）
if path == "/" or path == "":         → _serve_dashboard()
if path == "/api/models":             → _serve_api_models()
if path.startswith("/api/models/"):
    name = urllib.parse.unquote(path[len("/api/models/"):].rstrip("/"))
    if name:  → _serve_api_model_detail(name)
    else:     → 404（空 name）
else:         → 原有逻辑（.md 渲染 / 静态文件）
```

> 注：模型名通过 `urllib.parse.unquote` 解码，防止 URL 编码的 `-` 等字符导致查找失败。尾部斜线通过 `rstrip("/")` 规范化。

---

## 五、Dashboard 页面设计

### 页面结构

```
http://host:18999/
┌─────────────────────────────────────────────────────────┐
│  guofan 模型评估平台                           [刷新]    │
│  ─────────────────────────────────────────────────────  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │ 已完成    │  │ 进行中   │  │  合计    │             │
│  │    1     │  │    1     │  │    2     │             │
│  └──────────┘  └──────────┘  └──────────┘             │
│  ─────────────────────────────────────────────────────  │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │ tianji-querysafety   │  │ guoxue-72b-reason    │    │
│  │ ✅ 已完成  2026-03-16 │  │ 🔄 评估中             │    │
│  │ 类型：安全拦截        │  │ 类型：推理对话        │    │
│  │ 部署：4TP × L20      │  │ 部署：8TP × H100     │    │
│  │ 拐点：8.0 req/s      │  │ 拐点：—（进行中）    │    │
│  │ 建议：6 实例 × 24 卡 │  │                      │    │
│  │                      │  │                      │    │
│  │ [查看报告]            │  │ [查看进度]           │    │
│  │ 实验：               │  │ 实验：               │    │
│  │ · benchmark_20260312 │  │ · guoxue_partial_... │    │
│  │ · 4tp_fullrange_...  │  │ · logs/guoxue_8tp_.. │    │
│  │ · 4tp_vs_4dp_...     │  │                      │    │
│  └──────────────────────┘  └──────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### 交互行为

| 元素 | 行为 | 链接构建规则 |
|------|------|------|
| `[查看报告]` | 仅 `eval_status: completed` 且 `paths.eval_report` 非 null 时显示 | 剥离 `results/` 前缀：`/models/{name}/EVAL_REPORT.md` |
| `[查看进度]` | 仅 `eval_status: in_progress` 时显示 | 取 `linked_experiments` 中第一个 `logs/` 条目，构建绝对 URL：`http://host:8765/{name_without_logs_prefix}/progress.txt` |
| 实验列表（`results/` 条目） | 剥离 `results/` 前缀，链接到 `/REPORT.md`；若目录下无 REPORT.md（如仅含 HTML），则链接到目录入口 | 对 `guoxue_partial_20260317` 等仅有 HTML 的目录，链接到 `/guoxue_partial_20260317/` |
| 实验列表（`logs/` 条目） | 跳转到 8765 服务目录入口 | `http://host:8765/{name_without_logs_prefix}/` |
| `[刷新]` | 重新加载当前页（浏览器原生）| — |
| `performance: null` 或具体指标为 null | 显示"—"，不显示空值 | — |

> **链接辅助函数**（实现时参考，`_serve_dashboard` 调用时传入 `self`）：
> ```python
> def _exp_link(self, exp_path, logs_port=8765):
>     """构建 linked_experiments 条目的链接 URL。
>     host 从 HTTP 请求头获取，用于构建 logs/ 的绝对 URL。
>     文件存在性检查由本方法负责：results/ 条目若无 REPORT.md 则链接到目录入口。
>     """
>     host = self.headers.get("Host", "localhost").split(":")[0]
>     base_dir = self.directory   # 即 results/
>     if exp_path.startswith("results/"):
>         rel = exp_path[len("results/"):]
>         report_path = os.path.join(base_dir, rel, "REPORT.md")
>         if os.path.exists(report_path):
>             return f"/{rel}/REPORT.md"
>         else:
>             return f"/{rel}/"    # 目录入口（显示文件列表，包含 HTML 图表）
>     elif exp_path.startswith("logs/"):
>         rel = exp_path[len("logs/"):]
>         return f"http://{host}:{logs_port}/{rel}/"
>     return f"/{exp_path}/"
> ```

### 样式

复用 `serve.py` 现有 `_CSS`（GitHub 风格），追加卡片布局 CSS（flexbox grid）。无外部 CDN，无 JS 框架。

---

## 六、实现细节

### 文件变更

| 文件 | 变更 | 说明 |
|------|------|------|
| `scripts/serve.py` | 新增 3 个方法 + 修改 `do_GET` | 约 +120 行 |

**无新文件，无新依赖**（`yaml` 使用标准库 `tomllib` 替代？不，`yaml` 需要 `pyyaml`）

> ⚠️ **依赖确认**：解析 INDEX.yaml 需要 `pyyaml`。检查 `.venv` 是否已安装：
> ```bash
> .venv/bin/python -c "import yaml; print('ok')"
> ```
> 若未安装：`.venv/bin/pip install pyyaml`

### `do_GET` 修改（伪代码）

```python
def do_GET(self):
    parsed = urllib.parse.urlparse(self.path)
    path = parsed.path

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

    # 原有逻辑
    query = urllib.parse.parse_qs(parsed.query)
    is_raw = "raw" in query
    if path.lower().endswith(".md") and not is_raw:
        self._serve_markdown(path)
    else:
        super().do_GET()
```

### `summary.last_updated`（INDEX.yaml mtime）

```python
import datetime

def _get_index_mtime(self):
    """返回 INDEX.yaml 的修改时间（CST ISO 字符串），失败返回 None"""
    index_path = os.path.join(self.directory, "models", "INDEX.yaml")
    try:
        ts = os.path.getmtime(index_path)
        tz_cst = datetime.timezone(datetime.timedelta(hours=8))
        return datetime.datetime.fromtimestamp(ts, tz=tz_cst).isoformat()
    except Exception:
        return None
```

`_serve_api_models` 中计算 summary 时调用：
```python
summary = {
    "total": ..., "completed": ..., "in_progress": ..., "pending": ...,
    "last_updated": self._get_index_mtime()
}
```

---

### `performance` 规范化（统一为 dict with nulls）

```python
_PERFORMANCE_KEYS = [
    "sla_max_qps_rps", "sla_max_qps_rpm", "replay_success_rate",
    "replay_ttft_p90_s", "replay_e2e_p90_s"
]

def _normalize_model(model):
    """规范化单个模型条目：performance 保证为 dict（in_progress 时值全为 null）"""
    if model.get("performance") is None:
        model["performance"] = {k: None for k in _PERFORMANCE_KEYS}
    return model
```

在 `_serve_api_models` 和 `_serve_api_model_detail` 中，对所有模型条目调用 `_normalize_model` 后再序列化。

---

### `insights` 字段规范（INDEX.yaml 可选全局字段）

INDEX.yaml 可选顶层字段，记录跨模型技术发现：

```yaml
# 可选：跨模型技术发现（用于 Dashboard "💡 关键发现"区域）
insights:
  - "超长 Prompt（>4K）场景 DP 配置失效（tianji-4b 验证）"
  - "TP8/TP4 承载倍数 ≈ 1.6x，非 2x（ziwei-32b 验证）"

models:
  - ...
```

Dashboard 渲染逻辑：
- `insights` 存在且非空 → 在统计卡片下方渲染 `💡 关键发现` 区块，每条一行
- 不存在或为空 → 不渲染该区块（不影响卡片墙）

---

### EVAL_REPORT.md 存在性检查（Dashboard 卡片警告）

`_serve_dashboard` 渲染模型卡片前，对 `completed` 模型进行文件存在性验证：

```python
for model in models:
    if model.get("eval_status") == "completed":
        report_path = model.get("paths", {}).get("eval_report")
        if report_path and report_path.startswith("results/"):
            rel = report_path[len("results/"):]
            full_path = os.path.join(self.directory, rel)
            if not os.path.exists(full_path):
                model["_file_warning"] = f"⚠️ {report_path} 不存在"
```

卡片 HTML 中，若 `model._file_warning` 存在，在 `[查看报告]` 按钮前插入警告行：
```html
<p class="warn">⚠️ EVAL_REPORT.md 文件不存在，报告链接不可用</p>
```

---

### Dashboard 友好错误页（INDEX.yaml 不可用时）

`_serve_dashboard` 在 `_load_index` 返回 error 时渲染（HTTP 200 + HTML）：

```html
<h1>⚠️ 数据加载失败</h1>
<p><strong>错误信息：</strong>{error}</p>
<h3>可能原因：</h3>
<ul>
  <li>results/models/INDEX.yaml 被移动或删除</li>
  <li>serve.py 的 --directory 参数配置错误</li>
  <li>INDEX.yaml 格式错误（YAML 语法问题）</li>
</ul>
<h3>解决方法：</h3>
<ol>
  <li>检查 <code>results/models/INDEX.yaml</code> 是否存在</li>
  <li>验证语法：<code>python3 -c "import yaml; yaml.safe_load(open('results/models/INDEX.yaml'))"</code></li>
  <li>查看日志：<code>tail -f logs/data-pipeline/serve_18999.log</code></li>
</ol>
<p><a href="/">刷新页面</a></p>
```

使用现有 `_HTML_TEMPLATE` 渲染，`title` 为 `guofan Dashboard - 错误`。

---

### INDEX.yaml 解析（含错误处理）

```python
try:
    import yaml
except ImportError:
    raise RuntimeError("pyyaml not installed: run .venv/bin/pip install pyyaml")

def _load_index(self):
    """读取 INDEX.yaml，失败时返回 (None, error_str)，成功时返回 (data, None)"""
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
```

API 和 Dashboard 均先检查返回的 `error`，非 None 时：
- API 返回 HTTP 503 + `{"error": "index unavailable", "detail": "<错误描述>"}`
- Dashboard 返回 HTTP 200 + 最小 HTML 错误提示页（沿用现有 `_HTML_TEMPLATE`，body 内容为 `<h1>数据加载失败</h1><p>{error}</p><p><a href="javascript:location.reload()">刷新重试</a></p>`）

### JSON 响应辅助

```python
import datetime

def _json_default(obj):
    """处理 PyYAML 解析 date/datetime 为 Python 对象的情况"""
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")

def _send_json(self, data, status=200):
    body = json.dumps(data, ensure_ascii=False, indent=2,
                      default=_json_default).encode("utf-8")
    self.send_response(status)
    self.send_header("Content-Type", "application/json; charset=utf-8")
    self.send_header("Content-Length", str(len(body)))
    self.send_header("Access-Control-Allow-Origin", "*")   # openclaw 跨域调用
    self.end_headers()
    self.wfile.write(body)
```

---

## 七、部署与保活

现有进程已用 `nohup` 运行（pid 3382734），不需要改变启动方式。代码更新后：

```bash
# 1. 找到现有 serve.py 进程（results 服务，18999 端口）
ps aux | grep "serve.py 18999"

# 2. 杀掉重启
kill <pid>
nohup .venv/bin/python scripts/serve.py 18999 --bind 0.0.0.0 --directory results \
  > logs/data-pipeline/serve_18999.log 2>&1 &

# 3. 验证
curl http://localhost:18999/api/models | python3 -m json.tool
curl http://localhost:18999/ | head -30
```

---

## 八、验收标准

| 验收项 | 检查方式 |
|--------|------|
| `GET /api/models` 返回 200 + 合法 JSON，含 summary.pending 字段 | `curl localhost:18999/api/models` |
| `GET /api/models/tianji-querysafety-4b-v2-3` 返回完整条目 | `curl` 验证字段 |
| `GET /api/models/nonexistent` 返回 **404** + error JSON | `curl -o /dev/null -w "%{http_code}"` 验证状态码 |
| `GET /api/models/` （尾部斜线，name 为空）返回 404 | `curl` 验证 |
| INDEX.yaml 临时改名后 `GET /api/models` 返回 **503** | 手动测试，测完恢复 |
| `GET /` 返回 HTML，含模型卡片、统计数字 | 浏览器访问 |
| `completed` 模型显示 `[查看报告]`，`in_progress` 模型显示 `[查看进度]` | 浏览器核查卡片 |
| `performance: null` 模型的指标列全部显示"—" | 浏览器核查 guoxue 卡片 |
| Dashboard 中 `[查看报告]` 链接可点击且不 404 | 点击跳转验证 |
| Dashboard 中实验列表链接可点击（results/ 跳 18999，logs/ 跳 8765）| 逐链接验证 |
| 原 .md 渲染行为不受影响 | 访问 `/models/tianji-.../EVAL_REPORT.md` |
| 原静态文件服务不受影响 | 访问 `/models/tianji-.../model-context.md` |
| `GET /api/models` 响应头含 `Access-Control-Allow-Origin: *` | `curl -I` 查看响应头 |
| `summary.last_updated` 值与 INDEX.yaml mtime 一致 | `curl` 返回值 vs `stat results/models/INDEX.yaml` 对比 |
| `in_progress` 模型的 `performance` 为 dict（所有值为 null），非 null | `curl \| python3 -m json.tool` 验证 |
| INDEX.yaml 不存在时，`GET /` 返回含"可能原因 + 解决方法"的友好错误页 | 临时移走 INDEX.yaml 测试后恢复 |
| `completed` 模型的 EVAL_REPORT.md 文件被删除时，Dashboard 卡片显示警告 | 临时删除文件测试后恢复 |
| INDEX.yaml 含 `insights` 字段时，Dashboard 显示"💡 关键发现"区块 | 手动添加 insights 字段测试后恢复 |

---

## 九、执行清单

### 前置检查（阻断，不通过不继续）
- [ ] 确认 `pyyaml` 已安装：`.venv/bin/python -c "import yaml; print('ok')"` → 若失败先执行 `.venv/bin/pip install pyyaml`

### 代码修改
- [ ] 在 `scripts/serve.py` 顶部补充 `import json, datetime`，添加模块级 `_PERFORMANCE_KEYS` 常量和 `_json_default()` 函数
- [ ] 新增 `_load_index()` 方法（含 FileNotFoundError / YAMLError / 空数据三种错误处理，返回 `(data, error)` 元组）
- [ ] 新增 `_get_index_mtime()` 方法（读 INDEX.yaml mtime，返回 CST ISO 字符串）
- [ ] 新增模块级 `_normalize_model(model)` 函数（performance 规范化为 dict with nulls）
- [ ] 新增 `_send_json(data, status=200)` 方法（含 CORS 头、date 序列化）
- [ ] 新增 `_serve_dashboard()` 方法（读 INDEX.yaml，渲染卡片 HTML；含：存在性警告、insights 区块、友好错误页）
- [ ] 新增 `_serve_api_models()` 方法（含 summary.last_updated + summary.pending，所有模型经 `_normalize_model` 处理）
- [ ] 新增 `_serve_api_model_detail(name)` 方法（name 已 unquote，找不到返回 404，条目经 `_normalize_model` 处理）
- [ ] 修改 `do_GET`：在原有逻辑前插入 4 条路由拦截（`/`、`/api/models`、`/api/models/`、`/api/models/*`）

### 重启服务
- [ ] **语法检查**（必须通过才继续）：`python3 -m py_compile scripts/serve.py && echo "syntax ok"`
- [ ] 找到现有 18999 进程 pid：`ps aux | grep "serve.py 18999" | grep -v grep`
- [ ] `kill <pid> 2>/dev/null || true`（若进程已停止可跳过）
- [ ] 重启：`nohup .venv/bin/python scripts/serve.py 18999 --bind 0.0.0.0 --directory results > logs/data-pipeline/serve_18999.log 2>&1 &`
- [ ] 等待启动：`sleep 2 && curl -s localhost:18999/api/models | python3 -m json.tool | head -10`

### 验收
- [ ] 按第八节逐项验证（共 13 项）

### 提交
- [ ] `git add scripts/serve.py && git commit -m "feat: add dashboard and JSON API to serve.py"`
