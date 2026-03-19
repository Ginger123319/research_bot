#!/usr/bin/env python3
"""
提取 8TP QPS 扫描中所有"空响应"样本，生成中间分析数据。

空响应定义：
  - status == 200（HTTP 成功）
  - token_list 长度 == 2（仅 [START] + [DONE]，无实际 token 输出）

输出：
  logs/chart-32b-8tp-null-decode/
    ├── summary.md                 各 QPS 档位统计汇总
    ├── empty_responses_all.csv    所有空响应的完整记录
    └── user_query_clusters.md     user query 长度维度分析

用法：
  python3 scripts/analysis/extract_null_decode.py \
      --log-dir logs/chart-32b-8tp/qps_20260318_134151 \
      --out-dir logs/chart-32b-8tp-null-decode
"""

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

import pandas as pd

_PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_PROJECT / "third_party/speculative-decoding-benchmark"
                        "/3rdparty/llm-benchmark/src"))
from llm_benchmark.analysis.analysis.single_exp import load_exp_csv


# ── 工具函数 ──────────────────────────────────────────────────

def find_result_csv(qps_dir: Path) -> Path | None:
    candidates = [
        p for p in qps_dir.glob("*.csv")
        if not p.name.startswith("dataset") and not p.name.endswith(".argv.csv")
    ]
    return sorted(candidates)[-1] if candidates else None


def extract_qps_level(qps_dir: Path) -> float:
    try:
        return float(qps_dir.name.replace("qps_", ""))
    except ValueError:
        return 0.0


def parse_empty_rows(df: pd.DataFrame, qps_level: float) -> list[dict]:
    """从 DataFrame 中提取所有空响应行，返回 dict 列表。"""
    records = []
    for _, row in df.iterrows():
        tl = row["token_list"]
        # 空响应判定：token_list 只有 [START]+[DONE]，status=200
        is_empty = (
            isinstance(tl, list) and len(tl) == 2
            and row["status"] == 200
        )
        # 额外捕获非 200 的失败（502 等）
        is_http_error = (row["status"] != 200)

        if not (is_empty or is_http_error):
            continue

        # 解析 user_query 和 relation
        msgs = row.get("messages")
        user_query = ""
        relation = ""
        if isinstance(msgs, list):
            for m in msgs:
                if isinstance(m, dict):
                    if m.get("role") == "user":
                        user_query = m.get("content", "")
                    if m.get("role") == "system":
                        try:
                            sys_text = m.get("content", "")
                            # 提取 #UserInfo: 后面的 JSON 段
                            ui_start = sys_text.find("{")
                            ui_end = sys_text.find("}", ui_start) + 1
                            if ui_start >= 0 and ui_end > ui_start:
                                ui = json.loads(sys_text[ui_start:ui_end])
                                relation = ui.get("relation", "")
                        except Exception:
                            pass

        # 解析 matched_stop 和 ttfb
        matched_stop = None
        finish_reason = ""
        completion_tokens = None
        ttfb_ms = None

        rr = row.get("raw_response")
        if isinstance(rr, list):
            for entry in rr:
                d = entry.get("data")
                if isinstance(d, dict):
                    for ch in d.get("choices", []):
                        ms = ch.get("matched_stop")
                        fr = ch.get("finish_reason")
                        if ms is not None:
                            matched_stop = ms
                        if fr:
                            finish_reason = fr
                    usage = d.get("usage")
                    if usage and usage.get("completion_tokens") is not None:
                        completion_tokens = usage["completion_tokens"]

        if isinstance(tl, list) and len(tl) >= 2:
            t_start = tl[0].get("timestamp")
            t_end = tl[-1].get("timestamp")
            if t_start and t_end:
                ttfb_ms = round((t_end - t_start) * 1000, 2)

        records.append({
            "qps_level":         qps_level,
            "request_id":        row.get("request_id"),
            "fail_type":         "empty_response" if is_empty else "http_error",
            "status":            row["status"],
            "user_query":        user_query,
            "query_len":         len(user_query),
            "relation":          relation,
            "finish_reason":     finish_reason,
            "matched_stop":      matched_stop,
            "completion_tokens": completion_tokens,
            "ttfb_ms":           ttfb_ms,
            "prefill_len":       row.get("prefill_len"),
        })

    return records


# ── 主流程 ────────────────────────────────────────────────────

def run(log_dir: Path, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)

    qps_dirs = sorted(
        [d for d in log_dir.iterdir() if d.is_dir() and d.name.startswith("qps_")],
        key=lambda d: extract_qps_level(d)
    )

    all_records: list[dict] = []
    summary_rows: list[dict] = []

    for qps_dir in qps_dirs:
        qps_level = extract_qps_level(qps_dir)
        csv_path = find_result_csv(qps_dir)
        if csv_path is None:
            print(f"  [SKIP] {qps_dir.name}: 找不到结果 CSV")
            continue

        print(f"  [处理] {qps_dir.name} ← {csv_path.name}")
        df, err = load_exp_csv(str(csv_path))
        if df is None:
            print(f"    ❌ 加载失败: {err}")
            continue

        total = len(df)
        records = parse_empty_rows(df, qps_level)
        empty_cnt = sum(1 for r in records if r["fail_type"] == "empty_response")
        http_err_cnt = sum(1 for r in records if r["fail_type"] == "http_error")

        all_records.extend(records)
        summary_rows.append({
            "qps_level":    qps_level,
            "total":        total,
            "empty_cnt":    empty_cnt,
            "http_err_cnt": http_err_cnt,
            "fail_total":   len(records),
            "empty_rate":   f"{100 * empty_cnt / total:.2f}%",
            "fail_rate":    f"{100 * len(records) / total:.2f}%",
        })

    if not all_records:
        print("❌ 未提取到任何空响应记录")
        return

    # ── 写出 empty_responses_all.csv ─────────────────────────
    df_all = pd.DataFrame(all_records)
    csv_out = out_dir / "empty_responses_all.csv"
    df_all.to_csv(csv_out, index=False, encoding="utf-8-sig")
    print(f"\n✅ CSV 已写出: {csv_out}  ({len(df_all)} 条)")

    # ── 写出 summary.md ───────────────────────────────────────
    df_all_empty = df_all[df_all["fail_type"] == "empty_response"]
    total_all = sum(r["total"] for r in summary_rows)
    total_empty = sum(r["empty_cnt"] for r in summary_rows)
    total_http_err = sum(r["http_err_cnt"] for r in summary_rows)

    summary_lines = [
        "# xinghan-chart-32b-v1-1-agent 8TP — 空响应统计汇总\n",
        f"> 数据来源：`{log_dir}`\n",
        "## 各 QPS 档位明细\n",
        "| QPS | 总请求 | 空响应数 | 空响应率 | HTTP错误数 | 综合失败率 |",
        "|-----|--------|---------|---------|-----------|----------|",
    ]
    for r in summary_rows:
        summary_lines.append(
            f"| {r['qps_level']:.3f} "
            f"| {r['total']} "
            f"| {r['empty_cnt']} "
            f"| {r['empty_rate']} "
            f"| {r['http_err_cnt']} "
            f"| {r['fail_rate']} |"
        )
    summary_lines += [
        f"| **合计** | **{total_all}** "
        f"| **{total_empty}** "
        f"| **{100*total_empty/total_all:.2f}%** "
        f"| **{total_http_err}** "
        f"| **{100*(total_empty+total_http_err)/total_all:.2f}%** |",
        "",
        "## 空响应率趋势",
        "",
        "| 指标 | 值 |",
        "|------|-----|",
        f"| 最低空响应率档位 | {min(summary_rows, key=lambda x: x['empty_cnt']/x['total'])['qps_level']:.3f} QPS |",
        f"| 最高空响应率档位 | {max(summary_rows, key=lambda x: x['empty_cnt']/x['total'])['qps_level']:.3f} QPS |",
        f"| 空响应率均值 | {100*total_empty/total_all:.2f}% |",
        f"| 所有空响应 matched_stop=151645 占比 | "
        f"{100*df_all_empty['matched_stop'].eq(151645).sum()/len(df_all_empty):.1f}% |",
        f"| 所有空响应 completion_tokens=1 占比 | "
        f"{100*df_all_empty['completion_tokens'].eq(1).sum()/len(df_all_empty):.1f}% |",
    ]

    summary_md = out_dir / "summary.md"
    summary_md.write_text("\n".join(summary_lines), encoding="utf-8")
    print(f"✅ 汇总已写出: {summary_md}")

    # ── 写出 user_query_clusters.md ──────────────────────────
    cluster_lines = [
        "# user query 长度维度分析 — 空响应样本\n",
        f"> 样本数：{len(df_all_empty)} 条（来自 {len(qps_dirs)} 个 QPS 档位）\n",
    ]

    # 1. 长度分布
    cluster_lines += [
        "## 1. query 字符长度分布\n",
        "| 长度区间 | 空响应数 | 占空响应总数 % | 全量同区间总请求估算 |",
        "|---------|---------|-------------|-------------------|",
    ]
    bins = [(0, 4), (5, 9), (10, 19), (20, 39), (40, 99), (100, 9999)]
    bin_labels = ["≤4字", "5-9字", "10-19字", "20-39字", "40-99字", "≥100字"]
    for (lo, hi), label in zip(bins, bin_labels):
        cnt = ((df_all_empty["query_len"] >= lo) & (df_all_empty["query_len"] <= hi)).sum()
        pct = 100 * cnt / len(df_all_empty) if len(df_all_empty) > 0 else 0
        cluster_lines.append(f"| {label} | {cnt} | {pct:.1f}% | — |")
    cluster_lines.append("")

    # 2. 最短 query（≤4字）全文列出
    short_queries = df_all_empty[df_all_empty["query_len"] <= 4]["user_query"].tolist()
    cluster_lines += [
        "## 2. 极短问题（≤4字）完整列表\n",
        f"共 {len(short_queries)} 条：\n",
    ]
    for q in sorted(set(short_queries)):
        cnt = short_queries.count(q)
        cluster_lines.append(f"- `{q}`（出现 {cnt} 次）")
    cluster_lines.append("")

    # 3. 5-9字 样本
    mid_queries = df_all_empty[
        (df_all_empty["query_len"] >= 5) & (df_all_empty["query_len"] <= 9)
    ]["user_query"].tolist()
    cluster_lines += [
        "## 3. 短问题（5-9字）高频样本\n",
        f"共 {len(mid_queries)} 条，Top 20：\n",
    ]
    for q, cnt in Counter(mid_queries).most_common(20):
        cluster_lines.append(f"- `{q}`（{cnt} 次）")
    cluster_lines.append("")

    # 4. 长度统计指标
    ql = df_all_empty["query_len"]
    cluster_lines += [
        "## 4. 长度统计指标\n",
        "| 指标 | 值 |",
        "|------|-----|",
        f"| 均值 | {ql.mean():.1f} 字 |",
        f"| 中位数 | {ql.median():.1f} 字 |",
        f"| P90 | {ql.quantile(0.9):.1f} 字 |",
        f"| 最短 | {ql.min()} 字 |",
        f"| 最长 | {ql.max()} 字 |",
        "",
    ]

    # 5. 与全量对比（用 qps_4.000 档位做代表）
    ref_csv = log_dir / "qps_4.000" / "vanilla_qps4.000.csv"
    if ref_csv.exists():
        df_ref, _ = load_exp_csv(str(ref_csv))
        all_queries = []
        for _, row in df_ref.iterrows():
            msgs = row.get("messages")
            if isinstance(msgs, list):
                for m in msgs:
                    if isinstance(m, dict) and m.get("role") == "user":
                        all_queries.append(len(m.get("content", "")))
        if all_queries:
            s_ref = pd.Series(all_queries)
            cluster_lines += [
                "## 5. 与全量请求的长度对比（基于 qps_4.000 档位，6000条）\n",
                "| 指标 | 空响应样本 | 全量样本 |",
                "|------|-----------|---------|",
                f"| 均值 | {ql.mean():.1f} 字 | {s_ref.mean():.1f} 字 |",
                f"| 中位数 | {ql.median():.1f} 字 | {s_ref.median():.1f} 字 |",
                f"| ≤4字占比 | "
                f"{100*(ql<=4).sum()/len(ql):.1f}% | "
                f"{100*(s_ref<=4).sum()/len(s_ref):.1f}% |",
                f"| 5-9字占比 | "
                f"{100*((ql>=5)&(ql<=9)).sum()/len(ql):.1f}% | "
                f"{100*((s_ref>=5)&(s_ref<=9)).sum()/len(s_ref):.1f}% |",
                f"| ≥10字占比 | "
                f"{100*(ql>=10).sum()/len(ql):.1f}% | "
                f"{100*(s_ref>=10).sum()/len(s_ref):.1f}% |",
            ]

    cluster_md = out_dir / "user_query_clusters.md"
    cluster_md.write_text("\n".join(cluster_lines), encoding="utf-8")
    print(f"✅ 聚类分析已写出: {cluster_md}")
    print(f"\n📁 全部输出位于: {out_dir}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log-dir", default="logs/chart-32b-8tp/qps_20260318_134151")
    parser.add_argument("--out-dir", default="logs/chart-32b-8tp-null-decode")
    args = parser.parse_args()
    run(Path(args.log_dir), Path(args.out_dir))


if __name__ == "__main__":
    main()
