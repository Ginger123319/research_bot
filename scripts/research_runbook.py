#!/usr/bin/env python3
"""
Generate a research Runbook skeleton with:
- Source Relevance & Authority table
- Access checks (ok/blocked/not_found)
- Canonicalization + stable IDs
- docs/results + docs/sessions outputs (repo convention)

This script does NOT do web search. Provide seed URLs (and optional keywords)
then iterate by filling in relevance/authority manually (or in later automation).
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Iterable, Literal, Optional


Authority = Literal["S0", "S1", "S2"]
Access = Literal["ok", "blocked", "not_found"]
SourceType = Literal["doc", "code", "paper"]


def _today() -> dt.date:
    return dt.date.today()


def _slugify(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"[^\w\u4e00-\u9fff]+", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s[:60] or "topic"


def _strip_tracking_params(url: str) -> str:
    try:
        u = urllib.parse.urlsplit(url)
    except Exception:
        return url
    qs = urllib.parse.parse_qsl(u.query, keep_blank_values=True)
    filtered = []
    for k, v in qs:
        kl = k.lower()
        if kl.startswith("utm_"):
            continue
        if kl in {"gclid", "fbclid", "igshid", "spm", "ref", "source"}:
            continue
        filtered.append((k, v))
    new_query = urllib.parse.urlencode(filtered, doseq=True)
    # drop fragments for canonicalization
    return urllib.parse.urlunsplit((u.scheme, u.netloc, u.path, new_query, ""))


def canonicalize_url(url: str) -> str:
    url = url.strip()
    url = _strip_tracking_params(url)
    # normalize github "raw" vs "blob": keep as-is, but remove trailing slash
    url = url.rstrip("/")
    return url


def stable_id_from_canonical_url(canonical_url: str) -> str:
    h = hashlib.sha256(canonical_url.encode("utf-8")).hexdigest()
    return h[:16]


@dataclasses.dataclass(frozen=True)
class AccessResult:
    access: Access
    final_url: str
    status_code: Optional[int]
    error: Optional[str]
    last_modified: Optional[str] = None
    deprecation_notice: Optional[str] = None
    canonical_hint: Optional[str] = None


_DEPRECATION_PATTERNS = [
    r"this\s+(?:legacy|old|archived)\s+documentation",
    r"deprecated\s+soon",
    r"has\s+been\s+moved",
    r"has\s+moved\s+to",
    r"no\s+longer\s+maintained",
    r"please\s+use\s+the\s+new",
    r"see\s+the\s+new\s+documentation",
    r"archived\s+version",
]


def _extract_snippet(text: str, patterns: list[str]) -> Optional[str]:
    low = text.lower()
    for pat in patterns:
        m = re.search(pat, low)
        if m:
            start = max(0, m.start() - 80)
            end = min(len(text), m.end() + 200)
            raw = text[start:end].strip()
            raw = re.sub(r"\s+", " ", raw)
            return raw[:300]
    return None


def _extract_canonical(html: str) -> Optional[str]:
    m = re.search(
        r'<link[^>]+rel=["\']canonical["\'][^>]*href=["\']([^"\']+)["\']',
        html,
        flags=re.IGNORECASE,
    )
    if m:
        return m.group(1).strip()
    return None


def _fetch_and_inspect(url: str, timeout_s: float = 12.0) -> AccessResult:
    """
    Fetch URL via GET and record:
    - access status (ok/blocked/not_found)
    - Last-Modified header
    - deprecation banner snippet (if detected)
    - canonical link (if pointing elsewhere)
    """
    req = urllib.request.Request(
        url,
        method="GET",
        headers={"User-Agent": "research-bot/0.1 (+runbook-generator)"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            code = getattr(resp, "status", None)
            final_url = resp.geturl()
            last_modified = resp.headers.get("Last-Modified")
            content_type = (resp.headers.get("Content-Type") or "").lower()

            body = b""
            if "text/html" in content_type or final_url.lower().endswith((".html", "/", ".md")):
                body = resp.read(200_000)  # cap body to avoid huge pages

            text = ""
            if body:
                try:
                    text = body.decode("utf-8", errors="replace")
                except Exception:
                    text = ""

            deprecation = _extract_snippet(text, _DEPRECATION_PATTERNS) if text else None
            canonical = _extract_canonical(text) if text else None

            if code is not None and 200 <= code < 300:
                return AccessResult(
                    "ok", final_url, code, None,
                    last_modified=last_modified,
                    deprecation_notice=deprecation,
                    canonical_hint=canonical,
                )
            if code in (401, 403):
                return AccessResult("blocked", final_url, code, None)
            if code in (404, 410):
                return AccessResult("not_found", final_url, code, None)
            return AccessResult("blocked", final_url, code, None)
    except urllib.error.HTTPError as e:
        code = e.code
        final_url = getattr(e, "url", url) or url
        if code in (401, 403):
            return AccessResult("blocked", final_url, code, f"HTTP {code}")
        if code in (404, 410):
            return AccessResult("not_found", final_url, code, f"HTTP {code}")
        return AccessResult("blocked", final_url, code, f"HTTP {code}")
    except Exception as e:
        return AccessResult("blocked", url, None, f"{type(e).__name__}: {e}")


def check_access(url: str, timeout_s: float = 12.0) -> AccessResult:
    """
    Access policy (best-effort, deterministic):
    - 200-299: ok
    - 401/403: blocked
    - 404/410: not_found
    - other non-2xx: blocked (rate limit, server errors, etc.)

    Also inspects the response body for deprecation banners and canonical
    links so that stale/legacy docs are flagged as freshness warnings.
    """
    return _fetch_and_inspect(url, timeout_s=timeout_s)


def check_access_get_fallback(url: str, timeout_s: float = 12.0) -> AccessResult:
    return _fetch_and_inspect(url, timeout_s=timeout_s)


@dataclasses.dataclass
class SourceCandidate:
    id: str
    title: str
    type: SourceType
    authority: Authority
    relevance: int
    relevance_rationale: str
    access: Access
    url: str
    canonical_url: str
    retrieved_at: Optional[str]
    status_code: Optional[int]
    error: Optional[str]
    alternatives: list[dict]
    last_modified: Optional[str] = None
    deprecation_notice: Optional[str] = None
    canonical_hint: Optional[str] = None
    freshness_warning: Optional[str] = None


def infer_type_from_url(url: str) -> SourceType:
    u = url.lower()
    if "arxiv.org" in u or "doi.org" in u:
        return "paper"
    if "github.com" in u:
        return "code"
    return "doc"


def infer_authority_from_url(url: str) -> Authority:
    u = url.lower()
    if "github.com" in u:
        return "S0"
    if "arxiv.org" in u or "doi.org" in u:
        return "S0"
    # default conservative
    return "S1"


def build_candidates(seed_urls: Iterable[str]) -> list[SourceCandidate]:
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    candidates: list[SourceCandidate] = []
    seen: set[str] = set()

    for raw in seed_urls:
        if not raw.strip():
            continue
        canon = canonicalize_url(raw)
        if canon in seen:
            continue
        seen.add(canon)

        access_res = check_access(canon)
        final_canon = canonicalize_url(access_res.final_url)
        sid = stable_id_from_canonical_url(final_canon)

        warnings: list[str] = []
        if access_res.deprecation_notice:
            warnings.append(f"deprecation_notice: {access_res.deprecation_notice}")
        if access_res.canonical_hint:
            canon_hint_norm = canonicalize_url(access_res.canonical_hint)
            if canon_hint_norm not in (canon, final_canon):
                warnings.append(f"canonical_elsewhere: {access_res.canonical_hint}")
        # URL was silently redirected → the URL you provided is likely outdated
        # or renamed; the real content is now at final_canon. Surface this so
        # humans re-evaluate whether the provided URL is still the right source.
        if canon != final_canon:
            warnings.append(f"redirected_to: {final_canon}")
        freshness_warning = " | ".join(warnings) if warnings else None

        candidates.append(
            SourceCandidate(
                id=sid,
                title="(fill title)",
                type=infer_type_from_url(final_canon),
                authority=infer_authority_from_url(final_canon),
                relevance=2,
                relevance_rationale="(fill: why it matches this problem)",
                access=access_res.access,
                url=canon,
                canonical_url=final_canon,
                retrieved_at=now if access_res.access == "ok" else None,
                status_code=access_res.status_code,
                error=access_res.error,
                alternatives=[],
                last_modified=access_res.last_modified,
                deprecation_notice=access_res.deprecation_notice,
                canonical_hint=access_res.canonical_hint,
                freshness_warning=freshness_warning,
            )
        )
        # tiny delay to be polite
        time.sleep(0.15)

    return candidates


def sort_candidates(cands: list[SourceCandidate]) -> list[SourceCandidate]:
    auth_rank = {"S0": 0, "S1": 1, "S2": 2}
    access_rank = {"ok": 0, "blocked": 1, "not_found": 2}
    return sorted(
        cands,
        key=lambda c: (auth_rank.get(c.authority, 9), -c.relevance, access_rank.get(c.access, 9), c.canonical_url),
    )


def next_session_number(docs_sessions_dir: Path) -> int:
    if not docs_sessions_dir.exists():
        return 1
    nums = []
    for p in docs_sessions_dir.glob("*.md"):
        m = re.match(r"^(\d+)_", p.name)
        if m:
            nums.append(int(m.group(1)))
    return (max(nums) + 1) if nums else 1


def render_sources_table(cands: list[SourceCandidate]) -> str:
    lines = [
        "| Title | Type | Authority | Relevance | Access | Freshness | URL | Alternatives |",
        "|---|---|---:|---:|---|---|---|---|",
    ]
    for c in cands:
        rel = f"{c.relevance}（{c.relevance_rationale}）"
        alts = "；".join(a.get("url", "") for a in c.alternatives) if c.alternatives else "—"
        fresh_bits: list[str] = []
        if c.last_modified:
            fresh_bits.append(f"last-modified={c.last_modified}")
        if c.freshness_warning:
            fresh_bits.append(f"⚠ {c.freshness_warning}")
        freshness = "；".join(fresh_bits) if fresh_bits else "—"
        lines.append(
            f"| {c.title} | {c.type} | {c.authority} | {rel} | {c.access} | {freshness} | `{c.canonical_url}` | {alts} |"
        )
    return "\n".join(lines)


def write_runbook(
    repo_root: Path,
    date: dt.date,
    topic: str,
    problem_statement: str,
    success_criteria: str,
    environment: str,
    keywords: list[str],
    seed_urls: list[str],
    candidates: list[SourceCandidate],
    overwrite: bool,
) -> tuple[Path, Path]:
    docs_results = repo_root / "docs" / "results"
    docs_sessions = repo_root / "docs" / "sessions"
    docs_results.mkdir(parents=True, exist_ok=True)
    docs_sessions.mkdir(parents=True, exist_ok=True)

    slug = _slugify(topic)
    runbook_path = docs_results / f"{date.isoformat()}-{slug}-runbook.md"

    session_n = next_session_number(docs_sessions)
    session_path = docs_sessions / f"{session_n:02d}_{slug}_research.md"

    if runbook_path.exists() and not overwrite:
        raise SystemExit(f"Refusing to overwrite existing: {runbook_path} (use --overwrite)")
    if session_path.exists() and not overwrite:
        raise SystemExit(f"Refusing to overwrite existing: {session_path} (use --overwrite)")

    sources_table = render_sources_table(sort_candidates(candidates))

    runbook_md = f"""# Runbook：{problem_statement or topic}

> 调研日期：{date.isoformat()}
> 适用范围（版本/环境/前置条件）：{environment or "(fill)"}
> 成功判据（可测指标）：{success_criteria or "(fill)"}

## 阅读路径引导（<= 400 字）
(fill)

## 一句话摘要（最短可执行路径）
(fill)

## 0. Source Relevance & Authority（必出）

{sources_table}

## 1. 快速检查（~10 分钟）

- 动作：
  - 期望观测：
  - 若不满足跳转到：

## 2. 分支排查树（从观测到结论）
(fill)

## 3. 修复步骤（按无损→可回滚→破坏性）

### 3.1 Step：
- 目的：
- 动作：
- 验证点（必须可观测）：
- 风险：
- 回滚/兜底：
- 下一步分支：

## 4. 已验证关键主张（Claim Table）

| claim | 证据A | 证据B | 置信度(高/中/低) | 适用版本 | 备注 |
|---|---|---|---|---|---|
| (fill) | (fill) | (fill) | (fill) | (fill) | (fill) |

## 5. 局限性与待验证项
(fill)

## 6. 参考来源（URL 清单）
{chr(10).join([f"- `{c.canonical_url}`" for c in sort_candidates(candidates)])}
"""

    session_md = f"""# 会话记录：{topic}

> **日期**：{date.isoformat()}
> **会话目标**：产出 Runbook（原始材料优先 + 相关度分层 + 可访问性透明）

---

## 输入

- **问题（小切口）**：{problem_statement or "(fill)"}
- **成功判据**：{success_criteria or "(fill)"}
- **环境/约束**：{environment or "(fill)"}

## 召回信息

- **关键词**：{", ".join(keywords) if keywords else "(none)"}
- **种子 URL**：
{chr(10).join([f"  - `{canonicalize_url(u)}`" for u in seed_urls]) if seed_urls else "  - (none)"}

## Access 检测结果（结构化）

```json
{json.dumps([dataclasses.asdict(c) for c in sort_candidates(candidates)], ensure_ascii=False, indent=2)}
```

## 输出文件

- **Runbook**：`{runbook_path.relative_to(repo_root)}`
- **本会话记录**：`{session_path.relative_to(repo_root)}`
"""

    runbook_path.write_text(runbook_md, encoding="utf-8")
    session_path.write_text(session_md, encoding="utf-8")
    return runbook_path, session_path


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate research runbook skeleton from seed sources.")
    p.add_argument("--topic", required=True, help="Short topic name (used for filenames).")
    p.add_argument("--problem", default="", help="Small-cut problem statement for the runbook title.")
    p.add_argument("--success", default="", help="Measurable success criteria.")
    p.add_argument("--env", default="", help="Environment/constraints (k8s/baremetal/version/etc).")
    p.add_argument("--keyword", action="append", default=[], help="Keyword to record in the session log.")
    p.add_argument("--seed-url", action="append", default=[], help="Seed URL (official docs/code/paper). Repeatable.")
    p.add_argument("--date", default="", help="Date YYYY-MM-DD (default: today).")
    p.add_argument("--overwrite", action="store_true", help="Allow overwriting output files if they exist.")
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    repo_root = Path(__file__).resolve().parents[1]

    date = _today() if not args.date else dt.date.fromisoformat(args.date)
    seed_urls = args.seed_url or []

    candidates = build_candidates(seed_urls)
    runbook_path, session_path = write_runbook(
        repo_root=repo_root,
        date=date,
        topic=args.topic,
        problem_statement=args.problem,
        success_criteria=args.success,
        environment=args.env,
        keywords=args.keyword,
        seed_urls=seed_urls,
        candidates=candidates,
        overwrite=args.overwrite,
    )

    print(f"Wrote runbook:  {runbook_path}")
    print(f"Wrote session:  {session_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

