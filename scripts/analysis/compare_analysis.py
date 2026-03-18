#!/usr/bin/env python3
"""
多 CSV 横向对比分析脚本

对多个 benchmark 结果 CSV 生成完整的横向对比报告（Markdown 表格 + 可选 HTML 图表）。

所有指标（TTFT / TTFS / E2E / TPOT / 吞吐量）均通过 analysis_response() 正确计算，
其中 TTFS（Time to First Sentence，首句响应时间）需要解析 token_list 中的中文标点，
不能直接从 CSV 列读取，必须通过此脚本或 offline_analysis.py 计算。

用法：
    # 对比两个 CSV
    python scripts/analysis/compare_analysis.py \\
        --csv logs/exp_a/result_a.csv logs/exp_b/result_b.csv \\
        --names "版本A" "版本B"

    # 对比多个 CSV + 输出 HTML + Markdown
    python scripts/analysis/compare_analysis.py \\
        --csv logs/a.csv logs/b.csv logs/c.csv \\
        --names "0.4.6-r08" "0.4.6+2params-r08" "0.5.5-r08" \\
        --out results/compare_report.md \\
        --html results/compare_report.html

指标说明：
    TTFT   Time To First Token       首个 token 返回耗时（Prefill 延迟代理）
    TTFS   Time To First Sentence    首句完整返回耗时 = TTFT + 首句 decode 时间
                                     ⚠️  注意：TTFS ≠ TTFT，值通常比 TTFT 大 0.x~数秒
                                     ⚠️  注意：TTFS ≠ "Time to First Stream"（首字节）
    E2E    End-to-End latency        从发送到最后一个 token 的总时间
    TPOT   Inter-Token Latency       per-token 间隔（ITL，基于 token_list 精确计算）
    User-TPOT                        每请求平均 TPOT = (end - first_token) / completion_tokens
"""
import sys
import argparse
from pathlib import Path

import numpy as np
import pandas as pd

BENCH_SRC = Path("/mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party"
                 "/speculative-decoding-benchmark/3rdparty/llm-benchmark/src")
sys.path.insert(0, str(BENCH_SRC))

from llm_benchmark.analysis.analysis.single_exp import load_exp_csv, analysis_response


def _pct(arr, q):
    """计算单个百分位，arr 为 list/array，q 为 0-100 的整数。"""
    a = np.array([v for v in arr if v is not None], dtype=float)
    return float(np.percentile(a, q)) if len(a) > 0 else float("nan")


def _mean(arr):
    a = np.array([v for v in arr if v is not None], dtype=float)
    return float(a.mean()) if len(a) > 0 else float("nan")


def analyze_csv(csv_path: str) -> dict:
    """
    读取单个 benchmark CSV，运行 analysis_response()，返回完整指标字典。

    返回字典包含：
        name            - CSV 文件名（无后缀）
        csv_path        - 原始路径
        all_cnt         - 总请求数
        success_count   - 成功请求数
        success_rate    - 成功率（0~1）
        success_qps     - 成功 QPS
        total_duration  - 测试总耗时（秒）
        ttft_mean/p50/p90/p95/p99
        ttfs_mean/p50/p90/p95/p99  ← 通过 token_list 解析，非直接列读取
        e2e_mean/p50/p90/p95/p99
        tpot_mean       - ITL 均值（per-token）
        user_tpot_mean  - 每请求平均 TPOT
        prefill_throughput / decode_throughput / overall_throughput
        warning         - 分析警告信息
        error           - 错误信息（如果有）
    """
    result = {"csv_path": csv_path, "name": Path(csv_path).stem}

    df, err = load_exp_csv(csv_path)
    if err and df is None:
        result["error"] = err
        return result
    if err:
        result["warning"] = err

    analysis = analysis_response(df)
    metrics = analysis.get("metrics", {})
    plots = analysis.get("plots", {})
    latency_dist = plots.get("latency distribution", {}) if plots else {}

    result.update(metrics)

    # 计算完整分位数（TTFT / TTFS / E2E）
    for metric in ["ttft", "ttfs", "e2e"]:
        vals = latency_dist.get(metric, [])
        result[f"{metric}_mean"] = _mean(vals)
        for q in [50, 90, 95, 99]:
            result[f"{metric}_p{q}"] = _pct(vals, q)

    # User-TPOT 分位数
    ut_vals = latency_dist.get("user_tpot", [])
    result["user_tpot_p50"] = _pct(ut_vals, 50)
    result["user_tpot_p90"] = _pct(ut_vals, 90)
    result["user_tpot_p95"] = _pct(ut_vals, 95)

    if analysis.get("warning"):
        result.setdefault("warning", "")
        result["warning"] += analysis["warning"]

    return result


def _fmt(val, decimals=3, unit="s"):
    if val is None or (isinstance(val, float) and np.isnan(val)):
        return "N/A"
    return f"{val:.{decimals}f}{unit}"


def _pct_diff(base, cur):
    """相对于 base 的变化百分比，返回 "+x.x%" 或 "-x.x%" 字符串。"""
    if base is None or cur is None:
        return "N/A"
    if abs(base) < 1e-9:
        return "N/A"
    diff = (cur - base) / abs(base) * 100
    sign = "+" if diff >= 0 else ""
    return f"{sign}{diff:.1f}%"


def build_markdown_report(results: list[dict], base_index: int = 0) -> str:
    """生成 Markdown 格式的横向对比报告。"""
    names = [r["name"] for r in results]
    base = results[base_index]

    lines = []
    lines.append("# Benchmark 多实验横向对比报告\n")

    # ── 1. 基础信息 ──────────────────────────────────────────────
    lines.append("## 1. 基础信息\n")
    header = "| 指标 | " + " | ".join(names) + " |"
    sep    = "|------|" + "|".join(["------"] * len(names)) + "|"
    lines.append(header)
    lines.append(sep)

    def row(label, key, fmt_fn=None):
        cells = []
        for r in results:
            v = r.get(key)
            if fmt_fn:
                cells.append(fmt_fn(v))
            else:
                cells.append("N/A" if v is None else str(v))
        return f"| {label} | " + " | ".join(cells) + " |"

    lines.append(row("总请求数",    "all_cnt",      lambda v: str(int(v)) if v else "N/A"))
    lines.append(row("成功请求数",  "success_count",lambda v: str(int(v)) if v else "N/A"))
    lines.append(row("成功率",      "success_rate", lambda v: f"{v*100:.2f}%" if v else "N/A"))
    lines.append(row("测试总耗时",  "total_duration",lambda v: f"{v:.1f} s" if v else "N/A"))
    lines.append(row("成功 QPS",    "success_qps",  lambda v: f"{v:.3f} req/s" if v else "N/A"))
    lines.append("")

    # ── 2. 延迟分位数 ────────────────────────────────────────────
    lines.append("## 2. 延迟指标\n")
    lines.append(
        "> ⚠️  **指标说明**：\n"
        "> - **TTFT**（Time to First Token）：首个 token 返回耗时，= Prefill 延迟\n"
        "> - **TTFS**（Time to First **Sentence**，首句响应时间）：首句完整返回耗时，= TTFT + 首句 decode 时间\n"
        ">   - TTFS **值通常大于 TTFT**，两者不相等\n"
        ">   - TTFS **不是** \"Time to First Stream\"（首字节），如果看到 TTFS ≈ TTFT 说明 TTFS 计算有误\n"
        "> - **E2E**：端到端总响应时间\n"
        "> - **User-TPOT**：每请求平均 TPOT = (end - first_token) / completion_tokens\n"
    )

    def lat_section(metric_upper, metric_key, pcts):
        lines.append(f"### {metric_upper}\n")
        h = "| 分位数 | " + " | ".join(names)
        if len(names) > 1:
            h += f" | vs {names[base_index]}（基准）"
        h += " |"
        s = "|--------|" + "|".join(["------"] * len(names))
        if len(names) > 1:
            s += "|---------|"
        s += "|" if len(names) <= 1 else ""
        lines.append(h)
        lines.append(s)

        for label, key_suffix in [("Mean", "mean")] + [(f"P{q}", f"p{q}") for q in pcts]:
            key = f"{metric_key}_{key_suffix}"
            cells = [_fmt(r.get(key)) for r in results]
            row_str = f"| {label} | " + " | ".join(cells)
            if len(names) > 1:
                base_val = base.get(key)
                diffs = []
                for i, r in enumerate(results):
                    if i == base_index:
                        diffs.append("基准")
                    else:
                        diffs.append(_pct_diff(base_val, r.get(key)))
                row_str += " | " + " / ".join(diffs)
            row_str += " |"
            lines.append(row_str)
        lines.append("")

    lat_section("TTFT（首 Token 时间）", "ttft", [50, 90, 95, 99])
    lat_section("TTFS（首句响应时间）", "ttfs", [50, 90, 95, 99])
    lat_section("E2E（端到端总时间）",  "e2e",  [50, 90, 95, 99])

    # User-TPOT
    lines.append("### User-TPOT（每请求平均 TPOT）\n")
    h = "| 分位数 | " + " | ".join(names) + " |"
    s = "|--------|" + "|".join(["------"] * len(names)) + "|"
    lines.append(h)
    lines.append(s)
    for label, key in [("Mean", "user_tpot_mean"), ("P50", "user_tpot_p50"),
                       ("P90", "user_tpot_p90"), ("P95", "user_tpot_p95")]:
        cells = [_fmt(r.get(key)) for r in results]
        lines.append(f"| {label} | " + " | ".join(cells) + " |")
    lines.append("")

    # ── 3. 吞吐量 ────────────────────────────────────────────────
    lines.append("## 3. 吞吐量指标\n")
    h = "| 指标 | " + " | ".join(names) + " |"
    s = "|------|" + "|".join(["------"] * len(names)) + "|"
    lines.append(h)
    lines.append(s)
    for label, key in [("Prefill 吞吐", "prefill_throughput"),
                       ("Decode 吞吐",  "decode_throughput"),
                       ("Overall 吞吐", "overall_throughput")]:
        cells = [_fmt(r.get(key), decimals=1, unit=" tok/s") for r in results]
        lines.append(f"| {label} | " + " | ".join(cells) + " |")
    lines.append("")

    # ── 4. 警告 ──────────────────────────────────────────────────
    warnings = [(r["name"], r.get("warning") or r.get("error"))
                for r in results if r.get("warning") or r.get("error")]
    if warnings:
        lines.append("## 4. 警告与错误\n")
        for name, msg in warnings:
            lines.append(f"**{name}**: {msg}\n")

    return "\n".join(lines)


def build_html_report(results: list[dict]) -> str:
    """生成 HTML 格式的横向对比图表（CDF 叠加对比）。"""
    try:
        import plotly.graph_objects as go
        import plotly.io as pio
        from plotly.subplots import make_subplots
    except ImportError:
        return "<html><body><p>plotly 未安装，跳过 HTML 图表生成</p></body></html>"

    # 需要重新加载 latency distribution（compare_analysis 结果里不含原始列表）
    print("  [HTML] 重新加载各 CSV 的延迟原始数据（用于 CDF 图）...")
    lat_dists = []
    for r in results:
        df, _ = load_exp_csv(r["csv_path"])
        if df is None:
            lat_dists.append({})
            continue
        analysis = analysis_response(df)
        lat_dists.append(analysis.get("plots", {}).get("latency distribution", {}))

    colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
              "#8c564b", "#e377c2", "#7f7f7f"]

    metrics_info = [
        ("TTFT", "ttft"),
        ("TTFS (Time to First Sentence)", "ttfs"),
        ("E2E", "e2e"),
        ("User-TPOT", "user_tpot"),
    ]

    fig = make_subplots(rows=2, cols=2,
                        subplot_titles=[m[0] for m in metrics_info])

    for idx, (title, key) in enumerate(metrics_info):
        row, col = divmod(idx, 2)
        row += 1; col += 1
        for i, (r, lat) in enumerate(zip(results, lat_dists)):
            vals = lat.get(key, [])
            if not vals:
                continue
            arr = sorted(float(v) for v in vals if v is not None)
            n = len(arr)
            xs = [0.0] + arr
            ys = [0.0] + [(j + 1) / n for j in range(n)]
            fig.add_trace(go.Scatter(
                x=xs, y=ys, mode="lines",
                line=dict(shape="hv", color=colors[i % len(colors)]),
                name=r["name"],
                legendgroup=r["name"],
                showlegend=(idx == 0),
            ), row=row, col=col)

    fig.update_layout(
        height=800, title_text="Benchmark 多实验 CDF 对比",
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
    )
    for i in range(1, 5):
        row, col = divmod(i - 1, 2)
        fig.update_xaxes(title_text="Latency (s)", row=row + 1, col=col + 1)
        fig.update_yaxes(title_text="CDF", range=[0, 1.1], row=row + 1, col=col + 1)

    html_body = pio.to_html(fig, full_html=True, include_plotlyjs="cdn")
    return html_body


def main():
    parser = argparse.ArgumentParser(
        description="多 CSV 横向对比：通过 analysis_response() 正确计算 TTFS 等所有指标"
    )
    parser.add_argument(
        "--csv", nargs="+", required=True,
        help="一或多个 benchmark 结果 CSV 路径（空格分隔）"
    )
    parser.add_argument(
        "--names", nargs="+", default=None,
        help="对应的版本名称（可选，默认使用文件名）"
    )
    parser.add_argument(
        "--out", default=None,
        help="Markdown 报告输出路径（不传则仅打印到终端）"
    )
    parser.add_argument(
        "--html", default=None,
        help="HTML CDF 对比图输出路径（不传则跳过）"
    )
    parser.add_argument(
        "--base", type=int, default=0,
        help="基准 CSV 的索引（0-based，用于计算相对变化），默认为 0"
    )
    args = parser.parse_args()

    csv_paths = args.csv
    names = args.names or [None] * len(csv_paths)
    if len(names) < len(csv_paths):
        names = names + [None] * (len(csv_paths) - len(names))

    results = []
    for path, name in zip(csv_paths, names):
        print(f"[分析] {path} ...")
        r = analyze_csv(path)
        if name:
            r["name"] = name
        if r.get("error"):
            print(f"  ❌ 错误: {r['error']}")
        else:
            print(f"  ✅ {r['name']}: 成功率 {r.get('success_rate', 0)*100:.2f}%"
                  f"  TTFT P90={_fmt(r.get('ttft_p90'))}"
                  f"  TTFS P90={_fmt(r.get('ttfs_p90'))}  ← 注意: TTFS > TTFT 为正常"
                  f"  E2E P90={_fmt(r.get('e2e_p90'))}")
        results.append(r)

    # Markdown 报告
    print("\n" + "=" * 80)
    md = build_markdown_report(results, base_index=args.base)
    print(md)
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(md, encoding="utf-8")
        print(f"\n✅ Markdown 报告已保存: {args.out}")

    # HTML 报告（可选）
    if args.html:
        print(f"\n[HTML] 生成 CDF 对比图: {args.html} ...")
        html = build_html_report(results)
        Path(args.html).parent.mkdir(parents=True, exist_ok=True)
        Path(args.html).write_text(html, encoding="utf-8")
        print(f"✅ HTML 报告已保存: {args.html}")


if __name__ == "__main__":
    main()
