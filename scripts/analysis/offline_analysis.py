#!/usr/bin/env python3
"""
离线分析脚本：对 benchmark 结果 CSV 生成完整分析报告（HTML + 可选 PNG）

功能等价于 analysis web 客户端的"加载 → 分析"操作，无需启动 Dash 服务。

用法：
    # 仅生成 HTML
    python scripts/analysis/offline_analysis.py \
        --csv logs/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv \
        --out results/ziwei_relay_100rpm_analysis.html

    # 同时导出 PNG + 打印 REPORT.md 骨架
    python scripts/analysis/offline_analysis.py \
        --csv logs/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv \
        --out results/ziwei_replay_100rpm_analysis.html \
        --png-dir results/ziwei_benchmark_20260310_163524 \
        --model-name "xinghan-ziwei-32b-v1"

生成内容：
    HTML：
        - 核心指标汇总表（成功率 / TTFT / TPOT / E2E / 吞吐）
        - CDF 图：TTFT / TTFS / User-TPOT / ITL / E2E
        - Timeline 图：活跃请求数+RPS / 吞吐 / 延迟散点 / 成功率时序
        - Latency 分布直方图 / Token 长度分布直方图
    PNG（--png-dir 时额外生成）：
        - ttft_cdf.png / ttfs_cdf.png / user_tpot_cdf.png / itl_cdf.png / e2e_cdf.png
        - concurrency_timeline.png / success_rate_timeline.png
"""
import sys
import argparse
from pathlib import Path
from bisect import bisect_right
from datetime import datetime

import numpy as np
import pandas as pd
import plotly.graph_objects as go
import plotly.io as pio
from plotly.subplots import make_subplots
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

# ── 引入 llm_benchmark 分析模块 ─────────────────────────────
_PROJECT = Path(__file__).resolve().parents[2]
BENCH_SRC = _PROJECT / "third_party/llm-benchmark/src"
sys.path.insert(0, str(BENCH_SRC))

from llm_benchmark.analysis.analysis.single_exp import load_exp_csv, analysis_response


# ── CDF 图（复刻 page_home.build_cdf_figure）────────────────
def _downsample_for_cdf(values, max_points=2000):
    """对超大数据集做分位数降采样，保留 CDF 形状（尾部分位点不失真）。"""
    arr = np.array([v for v in values if v is not None], dtype=float)
    if len(arr) <= max_points:
        return arr.tolist()
    quantiles = np.linspace(0, 1, max_points)
    return np.quantile(arr, quantiles).tolist()


def build_cdf_figure(values, title):
    fig = go.Figure()
    try:
        if isinstance(values, pd.Series):
            clean = values.dropna().tolist()
        else:
            clean = [v for v in values if v is not None and not (isinstance(v, float) and pd.isna(v))]
        clean = sorted(float(v) for v in clean)
    except Exception:
        clean = []

    n = len(clean)
    if n == 0:
        fig.update_layout(height=400, width=520, title_text=title)
        return fig

    xs = clean
    ys = [(i + 1) / n for i in range(n)]
    x_max = max(xs) * 1.2
    step_x = [0.0] + xs
    step_y = [0.0] + ys

    fig.add_trace(go.Scatter(
        x=step_x, y=step_y, mode="lines",
        line=dict(shape="hv"),
        hovertemplate="值: %{x}<br>CDF: %{y:.3f}<extra></extra>",
    ))

    # P50 / P90 / P99 / P100 分位线
    s = pd.Series(xs)
    q_map = s.quantile([0.5, 0.9, 0.99, 1.0]).to_dict()
    bands = [("P50", 0.5, "#2ca02c"), ("P90", 0.9, "#ff7f0e"),
             ("P99", 0.99, "#d62728"), ("P100", 1.0, "#9467bd")]
    for label, q, color in bands:
        xq = float(q_map[q])
        yq = float(q)
        fig.add_shape(type="line", x0=xq, x1=xq, y0=0, y1=yq,
                      line=dict(color=color, width=1.5, dash="dot"))
        fig.add_shape(type="line", x0=0, x1=xq, y0=yq, y1=yq,
                      line=dict(color=color, width=1.2, dash="dot"))
        fig.add_trace(go.Scatter(x=[xq], y=[yq], mode="markers",
                                 marker=dict(color=color, size=6),
                                 hoverinfo="skip", showlegend=False))
        xanchor = "right" if xq > 0.8 * x_max else "left"
        ax = -30 if xanchor == "right" else 30
        ay = -15 if yq > 0.9 else 15
        if label == "P99":
            ax -= 12; ay += 12
        elif label == "P100":
            ax -= 24; ay -= 6
        fig.add_annotation(x=xq, y=yq, text=f"{label}: {xq:.3f}",
                           showarrow=True, arrowhead=2, arrowsize=1,
                           arrowwidth=1, arrowcolor=color,
                           font=dict(size=10, color=color), ax=ax, ay=ay,
                           bgcolor="rgba(255,255,255,0.65)",
                           bordercolor=color, borderwidth=0.5, opacity=0.95)

    # 均值线
    mean_x = float(s.mean())
    mean_y = bisect_right(xs, mean_x) / n
    color = "#1f77b4"
    fig.add_shape(type="line", x0=mean_x, x1=mean_x, y0=0, y1=mean_y,
                  line=dict(color=color, width=1.5, dash="dash"))
    fig.add_shape(type="line", x0=0, x1=mean_x, y0=mean_y, y1=mean_y,
                  line=dict(color=color, width=1.2, dash="dash"))
    fig.add_trace(go.Scatter(x=[mean_x], y=[mean_y], mode="markers",
                             marker=dict(color=color, size=6),
                             hoverinfo="skip", showlegend=False))
    xanchor = "right" if mean_x > 0.8 * x_max else "left"
    ax = -30 if xanchor == "right" else 30
    ay = -15 if mean_y > 0.9 else 15
    fig.add_annotation(x=mean_x, y=mean_y,
                       text=f"Mean: x={mean_x:.3f}, y={mean_y:.3f}",
                       showarrow=True, arrowhead=2, arrowsize=1,
                       arrowwidth=1, arrowcolor=color,
                       font=dict(size=10, color=color), ax=ax, ay=ay,
                       bgcolor="rgba(255,255,255,0.65)",
                       bordercolor=color, borderwidth=0.5, opacity=0.95)

    fig.update_layout(height=500, width=520, showlegend=False,
                      margin=dict(l=28, r=8, t=30, b=28), title_text=title)
    fig.update_xaxes(title_text=f"{title} (s)", range=[0, x_max], autorange=False,
                     tickfont=dict(size=10), title_font=dict(size=11))
    fig.update_yaxes(title_text="CDF", range=[0, 1.2], autorange=False,
                     tickfont=dict(size=10), title_font=dict(size=11))
    return fig


# ── Timeline 图（复刻 page_home.build_timeline_figure）────────
def build_timeline_figures(timeline_plots):
    meta = timeline_plots["meta"]
    time_min, time_max = meta["x_min"], meta["x_max"]
    figures = timeline_plots["figures"]

    # 1. 活跃请求 + RPS + CPS
    req_fig = go.Figure()
    req_fig.add_trace(go.Scatter(
        x=figures["requests"]["# of active requests"]["x"],
        y=figures["requests"]["# of active requests"]["y"],
        mode="lines", name="Active", line=dict(color="blue", width=2, shape="hv")))
    req_fig.add_trace(go.Scatter(
        x=figures["requests"]["rps"]["x"], y=figures["requests"]["rps"]["y"],
        mode="lines", name="RPS", line=dict(color="green", width=2, shape="hv")))
    req_fig.add_trace(go.Scatter(
        x=figures["requests"]["cps"]["x"], y=figures["requests"]["cps"]["y"],
        mode="lines", name="CPS", line=dict(color="orange", width=2, shape="hv")))
    req_fig.update_layout(
        title_text="活跃请求数 / RPS / CPS",
        yaxis=dict(title="count"), xaxis=dict(range=[time_min, time_max]), height=350)

    # 2. 吞吐
    thr_fig = go.Figure()
    thr_fig.add_trace(go.Scatter(
        x=figures["throughput"]["prefill_throughput"]["x"],
        y=figures["throughput"]["prefill_throughput"]["y"],
        mode="lines", name="Prefill", line=dict(color="orange", shape="hv")))
    if figures["throughput"].get("decode_throughput"):
        thr_fig.add_trace(go.Scatter(
            x=figures["throughput"]["decode_throughput"]["x"],
            y=figures["throughput"]["decode_throughput"]["y"],
            mode="lines", name="Decode", line=dict(color="green", shape="hv")))
    if figures["throughput"].get("overall_throughput"):
        thr_fig.add_trace(go.Scatter(
            x=figures["throughput"]["overall_throughput"]["x"],
            y=figures["throughput"]["overall_throughput"]["y"],
            mode="lines", name="Overall", line=dict(color="blue", shape="hv")))
    thr_fig.update_layout(
        title_text="吞吐量 (tok/s)",
        yaxis_title="tok/s", xaxis=dict(range=[time_min, time_max]), height=350)

    # 3. 延迟散点（TTFT / TTFS / User-TPOT / E2E）
    lat_fig = go.Figure()
    for key, color in [("ttft", "orange"), ("ttfs", "blue"),
                       ("user_tpot", "green"), ("e2e", "red")]:
        d = figures["latency"].get(key, {})
        if d:
            lat_fig.add_trace(go.Scatter(
                x=d["x"], y=d["y"], mode="markers",
                name=key.upper().replace("_", "-"),
                marker=dict(color=color, size=3)))
    lat_fig.update_layout(
        title_text="延迟散点（TTFT / TTFS / User-TPOT / E2E）",
        yaxis_title="Latency (s) of requests",
        xaxis=dict(range=[time_min, time_max]), height=400)

    # 4. 请求成功率（按每 15s 窗口统计过去 60s 的成功率）
    sr_data = figures["requests"].get("request success rate", {})
    sr_fig = go.Figure()
    if sr_data:
        sr_fig.add_trace(go.Scatter(
            x=sr_data["x"], y=sr_data["y"],
            mode="lines", name="Success Rate",
            line=dict(color="green", shape="linear")))
    sr_fig.update_xaxes(range=[time_min, time_max], showgrid=True, tickangle=-20)
    sr_fig.update_yaxes(title_text="Success Rate (%)",
                        tickformat=".1f", dtick=20)
    sr_fig.update_layout(
        title_text="请求成功率 Timeline（60s 滑动窗口，15s 采样）",
        xaxis=dict(range=[time_min, time_max]), height=350)

    return req_fig, thr_fig, lat_fig, sr_fig


def _prebinned_hist(vals, n_bins, x_min, x_max, name, opacity=0.75):
    """将原始数据预计算为直方图 bin，避免全量序列化到 HTML（节省体积）。"""
    arr = np.array([v for v in vals if v is not None], dtype=float)
    counts, edges = np.histogram(arr, bins=n_bins, range=(x_min, x_max))
    probs = counts / counts.sum() if counts.sum() > 0 else counts.astype(float)
    return go.Bar(
        x=edges[:-1],
        y=probs,
        width=(edges[1] - edges[0]),
        name=name,
        opacity=opacity,
        offset=0,
    )


def _series_p99(vals):
    """返回一组值的 P99，用于裁剪长尾、避免直方图 bin 过宽。"""
    arr = np.array([v for v in vals if v is not None], dtype=float)
    return float(np.percentile(arr, 99)) if len(arr) > 0 else 1.0


# ── Token 长度直方图（每个系列按自身 P99 裁剪，避免 first_sentence 等被压缩）
def build_token_hist(token_len_dist):
    fig = go.Figure()
    for key in ["prompt", "completion", "all", "first_sentence"]:
        vals = token_len_dist.get(key, [])
        if not vals:
            continue
        # 每个系列独立计算 P99 作为 x_max，防止长尾导致 bin 过宽
        x_max = max(_series_p99(vals) * 1.05, 1.0)
        fig.add_trace(_prebinned_hist(
            vals, n_bins=100, x_min=0, x_max=x_max,
            name=f"{key}: {len(vals)} counts",
        ))
    fig.update_layout(
        title_text="Token Length Distribution",
        barmode="overlay",
        height=500,
        updatemenus=[dict(
            type="buttons",
            direction="right",
            x=0.0, xanchor="left", y=1.15,
            buttons=[
                dict(label=k,
                     method="update",
                     args=[{"visible": [i == j for j in range(
                         len([kk for kk in ["prompt", "completion", "all", "first_sentence"]
                              if token_len_dist.get(kk)])
                     )]}])
                for i, k in enumerate(
                    [kk for kk in ["prompt", "completion", "all", "first_sentence"]
                     if token_len_dist.get(kk)]
                )
            ] + [dict(label="All", method="update",
                      args=[{"visible": [True] * len(
                          [kk for kk in ["prompt", "completion", "all", "first_sentence"]
                           if token_len_dist.get(kk)]
                      )}])]
        )]
    )
    fig.update_xaxes(title_text="Token Length", autorange=True)
    fig.update_yaxes(title_text="Probability", autorange=True)
    return fig


# ── Latency 分布直方图（全部指标，各系列按 P99 裁剪长尾）
def build_latency_hist(latency_dist):
    fig = go.Figure()
    for key in ["tpot", "user_tpot", "ttft", "ttfs", "e2e"]:
        vals = latency_dist.get(key, [])
        if not vals:
            continue
        x_max = max(_series_p99(vals) * 1.05, 0.001)
        fig.add_trace(_prebinned_hist(
            vals, n_bins=100, x_min=0, x_max=x_max,
            name=f"{key}: {len(vals)} counts",
        ))
    fig.update_layout(title_text="Latency Distribution",
                      barmode="overlay", height=500)
    fig.update_xaxes(title_text="Latency (s)", autorange=True)
    fig.update_yaxes(title_text="Probability", autorange=True)
    return fig


# ── 分位数计算 ────────────────────────────────────────────────
def compute_percentiles(latency_dist):
    """计算 TTFT / TTFS / E2E 的 P50/P90/P95/P99，供汇总表和 REPORT 骨架使用。"""
    result = {}
    for metric in ["ttft", "ttfs", "e2e"]:
        vals = latency_dist.get(metric, [])
        if vals:
            arr = np.array([v for v in vals if v is not None], dtype=float)
            for pct, label in [(50, "p50"), (90, "p90"), (95, "p95"), (99, "p99")]:
                result[f"{metric}_{label}"] = float(np.percentile(arr, pct))
    return result


# ── 指标汇总表 ────────────────────────────────────────────────
def metrics_to_html(metrics, csv_name, percentiles=None):
    m = metrics
    p = percentiles or {}
    lat = {
        "ttft": m.get("ttft_mean", 0),
        "ttfs": m.get("ttfs_mean", 0),
        "tpot": m.get("tpot_mean", 0),
        "e2e":  m.get("e2e_mean", 0),
    }

    def _pval(key):
        v = p.get(key)
        return f"{v:.3f} s" if v is not None else "—"

    rows = [
        ("实验文件",         csv_name),
        ("总请求数",         f"{int(m['all_cnt'])}"),
        ("成功数",           f"{int(m['success_count'])}"),
        ("成功率",           f"{m['success_rate']*100:.2f}%"),
        ("实际成功 QPS",     f"{m['success_qps']:.3f} req/s"),
        ("总耗时",           f"{m['total_duration']:.1f} s"),
        ("",                 ""),
        ("TTFT 均值",        f"{lat['ttft']:.3f} s"),
        ("TTFT P50",         _pval("ttft_p50")),
        ("TTFT P90",         _pval("ttft_p90")),
        ("TTFT P95",         _pval("ttft_p95")),
        ("TTFT P99",         _pval("ttft_p99")),
        ("",                 ""),
        ("TTFS 均值",        f"{lat['ttfs']:.3f} s"),
        ("TTFS P90",         _pval("ttfs_p90")),
        ("",                 ""),
        ("E2E 均值",         f"{lat['e2e']:.3f} s"),
        ("E2E P50",          _pval("e2e_p50")),
        ("E2E P90",          _pval("e2e_p90")),
        ("E2E P95",          _pval("e2e_p95")),
        ("E2E P99",          _pval("e2e_p99")),
        ("",                 ""),
        ("TPOT 均值",        f"{lat['tpot']:.3f} s"),
        ("",                 ""),
        ("Prefill 吞吐",     f"{m['prefill_throughput']:.1f} tok/s"),
        ("Decode 吞吐",      f"{m['decode_throughput']:.1f} tok/s"),
        ("Overall 吞吐",     f"{m['overall_throughput']:.1f} tok/s"),
    ]
    rows_html = "".join(
        f"<tr><td style='padding:4px 12px;font-weight:bold'>{k}</td>"
        f"<td style='padding:4px 12px'>{v}</td></tr>"
        for k, v in rows if k != ""
    )
    return f"""
    <h2>核心指标</h2>
    <table border='1' cellspacing='0' style='border-collapse:collapse;font-size:14px'>
      {rows_html}
    </table>
    """


# ── matplotlib PNG 导出函数 ───────────────────────────────────

def _mpl_cdf(ax, values, title, color="#1f77b4"):
    """在给定 axes 上绘制经验 CDF，标注 P50/P90/P99/P100/Mean。"""
    arr = np.array([v for v in values if v is not None], dtype=float)
    arr.sort()
    n = len(arr)
    if n == 0:
        ax.set_title(title)
        return
    ys = np.arange(1, n + 1) / n
    ax.step(np.concatenate([[0], arr]), np.concatenate([[0], ys]),
            where="post", color=color, linewidth=1.5)
    ax.set_xlim(0, arr.max() * 1.15)
    ax.set_ylim(0, 1.15)
    ax.set_xlabel(f"{title} (s)", fontsize=10)
    ax.set_ylabel("CDF", fontsize=10)
    ax.set_title(title, fontsize=11)
    ax.grid(True, alpha=0.3)

    s = pd.Series(arr)
    bands = [("P50", 0.50, "#2ca02c"), ("P90", 0.90, "#ff7f0e"),
             ("P99", 0.99, "#d62728"), ("P100", 1.00, "#9467bd")]
    for label, q, c in bands:
        xq = float(s.quantile(q))
        yq = q
        ax.axvline(xq, ymax=yq / 1.15, color=c, linewidth=1.2, linestyle=":")
        ax.axhline(yq, xmax=(xq / (arr.max() * 1.15)), color=c, linewidth=1.0, linestyle=":")
        ax.annotate(f"{label}={xq:.3f}s", xy=(xq, yq),
                    xytext=(6, -4), textcoords="offset points",
                    fontsize=8, color=c)
    mean_x = float(s.mean())
    mean_y = float(bisect_right(arr, mean_x)) / n
    ax.axvline(mean_x, ymax=mean_y / 1.15, color="#1f77b4", linewidth=1.2, linestyle="--")
    ax.annotate(f"Mean={mean_x:.3f}s", xy=(mean_x, mean_y),
                xytext=(6, 4), textcoords="offset points",
                fontsize=8, color="#1f77b4")


def export_cdf_pngs(latency_dist, png_dir: Path):
    """导出 5 张 CDF PNG：ttft / ttfs / user_tpot / itl / e2e。"""
    specs = [
        ("ttft",     "ttft_cdf.png",     "TTFT",         "#ff7f0e"),
        ("ttfs",     "ttfs_cdf.png",     "TTFS",         "#2ca02c"),
        ("user_tpot","user_tpot_cdf.png","User-TPOT",    "#9467bd"),
        ("tpot",     "itl_cdf.png",      "ITL (per-token TPOT)", "#8c564b"),
        ("e2e",      "e2e_cdf.png",      "E2E",          "#d62728"),
    ]
    saved = []
    for key, fname, title, color in specs:
        vals = latency_dist.get(key, [])
        if not vals:
            continue
        # ITL 数据量大，降采样
        if key == "tpot" and len(vals) > 5000:
            vals = _downsample_for_cdf(vals, max_points=5000)
        fig, ax = plt.subplots(figsize=(6, 4.5), dpi=120)
        _mpl_cdf(ax, vals, title, color=color)
        fig.tight_layout()
        out = png_dir / fname
        fig.savefig(out, bbox_inches="tight")
        plt.close(fig)
        saved.append((fname, title))
        print(f"   PNG: {out}")
    return saved


def export_timeline_pngs(timeline_plots, png_dir: Path):
    """导出 2 张 Timeline PNG：concurrency + success_rate。"""
    meta = timeline_plots["meta"]
    figs_data = timeline_plots["figures"]
    saved = []

    # 1. 并发 Timeline（活跃请求数 + RPS）
    fig, ax = plt.subplots(figsize=(10, 3.5), dpi=120)
    req = figs_data["requests"]
    ax.step(req["# of active requests"]["x"], req["# of active requests"]["y"],
            where="post", color="#1f77b4", label="Active Requests", linewidth=1.5)
    ax2 = ax.twinx()
    ax2.step(req["rps"]["x"], req["rps"]["y"],
             where="post", color="#2ca02c", label="RPS", linewidth=1.2, alpha=0.8)
    ax2.step(req["cps"]["x"], req["cps"]["y"],
             where="post", color="#ff7f0e", label="CPS", linewidth=1.2, alpha=0.8)
    ax.set_ylabel("Active Requests", color="#1f77b4", fontsize=9)
    ax2.set_ylabel("RPS / CPS", fontsize=9)
    ax.set_xlabel("Time", fontsize=9)
    ax.set_title("Active Requests / RPS / CPS Timeline", fontsize=11)
    ax.tick_params(axis="x", rotation=20, labelsize=8)
    lines1, labels1 = ax.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax.legend(lines1 + lines2, labels1 + labels2, fontsize=8, loc="upper right")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    out = png_dir / "concurrency_timeline.png"
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)
    saved.append(("concurrency_timeline.png", "并发 Timeline"))
    print(f"   PNG: {out}")

    # 2. Success Rate Timeline
    sr = req.get("request success rate", {})
    if sr:
        fig, ax = plt.subplots(figsize=(10, 3), dpi=120)
        ax.plot(sr["x"], sr["y"], color="#2ca02c", linewidth=1.5)
        ax.set_ylim(0, 115)
        ax.yaxis.set_major_formatter(mticker.FormatStrFormatter("%.0f%%"))
        ax.set_xlabel("Time", fontsize=9)
        ax.set_ylabel("Success Rate", fontsize=9)
        ax.set_title("Success Rate Timeline (60s window, 15s sample)", fontsize=11)
        ax.tick_params(axis="x", rotation=20, labelsize=8)
        ax.grid(True, alpha=0.3)
        fig.tight_layout()
        out = png_dir / "success_rate_timeline.png"
        fig.savefig(out, bbox_inches="tight")
        plt.close(fig)
        saved.append(("success_rate_timeline.png", "成功率 Timeline"))
        print(f"   PNG: {out}")

    return saved


def print_report_skeleton(metrics, png_dir: Path, model_name: str, csv_path: Path, percentiles=None):
    """在终端打印 REPORT.md 骨架，包含预填数字、图片引用、Grafana 提示。"""
    m = metrics
    p = percentiles or {}
    now = datetime.now().strftime("%Y-%m-%d")

    def _pval(key, fallback="<见图>"):
        v = p.get(key)
        return f"{v:.3f} s" if v is not None else fallback

    skeleton = f"""
╔══════════════════════════════════════════════════════════════╗
  REPORT.md 骨架（复制到 {png_dir}/REPORT.md 后补充分析段落）
╚══════════════════════════════════════════════════════════════╝

# {model_name} 性能验证报告

> **测试时间**：{now}
> **测试目标服务**：<填写服务 URL>
> **结论**：✅ / ❌ <一句话结论>

---

## 一、背景与目的

> <请填写迁移/上线背景和测试目标>

---

## 二、测试方法论

### 2.1 测试数据构建流程

> <参考 traffic-dataset-prep Skill 描述数据处理过程>

### 2.2 压测执行参数

| 参数 | 值 |
|------|-----|
| 数据集 | `{csv_path.name}` |
| 请求模式 | `--keep-income-time`（按真实到达时间回放）|
| KV Cache | `--no-kvcache` |
| max_completion_tokens | <填写> |
| 数据来源 | `{csv_path}` |

---

## 三、测试结果汇总

### 3.1 可用性指标

| 指标 | 值 |
|------|-----|
| 总请求数 | {int(m['all_cnt'])} |
| 成功请求数 | {int(m['success_count'])} |
| **成功率** | **{m['success_rate']*100:.2f}%** |
| 失败请求数 | {int(m['all_cnt']) - int(m['success_count'])} |
| 测试总耗时 | {m['total_duration']:.1f} s（≈ {m['total_duration']/60:.0f} 分钟）|
| 实测 QPS | {m['success_qps']:.3f} req/s |

### 3.2 延迟分布（CDF 分位数）

#### TTFT（首 Token 时间）

| 分位数 | 值 |
|--------|----|
| Mean   | {m['ttft_mean']:.3f} s |
| P50    | {_pval('ttft_p50')} |
| P90    | {_pval('ttft_p90')} |
| P95    | {_pval('ttft_p95')} |
| P99    | {_pval('ttft_p99')} |
![TTFT CDF](ttft_cdf.png)

#### TTFS（首句响应时间）

| 分位数 | 值 |
|--------|----|
| Mean   | {m['ttfs_mean']:.3f} s |
| P90    | {_pval('ttfs_p90')} |

![TTFS CDF](ttfs_cdf.png)

#### E2E（端到端总响应时间）

| 分位数 | 值 |
|--------|----|
| Mean   | {m['e2e_mean']:.3f} s |
| P50    | {_pval('e2e_p50')} |
| P90    | {_pval('e2e_p90')} |
| P95    | {_pval('e2e_p95')} |
| P99    | {_pval('e2e_p99')} |

![E2E CDF](e2e_cdf.png)

#### TPOT / ITL（逐 Token 生成时间）

| 分位数 | 值 |
|--------|----|
| Mean (User-TPOT) | {m['user_tpot_mean']:.3f} s |
| Mean (ITL) | {m['tpot_mean']:.3f} s |

![ITL CDF](itl_cdf.png)

### 3.3 吞吐量指标

| 指标 | 值 |
|------|-----|
| Prefill 吞吐量 | {m['prefill_throughput']:.1f} tokens/s |
| Decode 吞吐量 | {m['decode_throughput']:.1f} tokens/s |
| 综合吞吐量 | {m['overall_throughput']:.1f} tokens/s |

### 3.4 并发与成功率时间线

![并发 Timeline](concurrency_timeline.png)
![成功率 Timeline](success_rate_timeline.png)

---

## 四、有效性论证

> <请填写：数据真实性、流量压力充分性、与线上监控的横向对比>

### 4.x 与 Grafana 线上监控的横向比对

> ⚠️  **请手动截图 Grafana 监控面板并放置到本目录**
>
>     监控地址：http://172.21.52.62:3000/d/cb7f886a-289f-4052-ae50-913644582b64/geniuworks
>     建议截取：TTFT / E2E / RPM 面板，时间范围对齐本次测试时段
>
> 截图保存为：`grafana_snapshot.png`，引用方式：
>
>     ![Grafana 线上监控](grafana_snapshot.png)

---

## 五、结论与上线建议

### 5.1 综合结论

| 验证项 | 结论 |
|--------|------|
| 可用性（成功率 > 99.9%）| {'✅' if m['success_rate'] > 0.999 else '❌'} {m['success_rate']*100:.2f}% |
| TTFT P90 | {_pval('ttft_p90')} |
| E2E P90  | {_pval('e2e_p90')} |
| E2E P95  | {_pval('e2e_p95')} |
| 峰值压力覆盖 | <填写 RPM> |

### 5.2 上线建议

> <请填写>

---

## 六、附录

### 6.1 原始数据摘要

```
total_duration:      {m['total_duration']:.3f} s
all_cnt:             {int(m['all_cnt'])}
success_count:       {int(m['success_count'])}
success_rate:        {m['success_rate']:.4f} ({m['success_rate']*100:.2f}%)
success_qps:         {m['success_qps']:.3f} req/s
ttft_mean:           {m['ttft_mean']:.3f} s
ttfs_mean:           {m['ttfs_mean']:.3f} s
tpot_mean:           {m['tpot_mean']:.3f} s
user_tpot_mean:      {m['user_tpot_mean']:.3f} s
e2e_mean:            {m['e2e_mean']:.3f} s
prefill_throughput:  {m['prefill_throughput']:.3f} tokens/s
decode_throughput:   {m['decode_throughput']:.3f} tokens/s
overall_throughput:  {m['overall_throughput']:.3f} tokens/s
```

### 6.2 数据来源

- 原始数据：`{csv_path}`
- HTML 报告：见同级目录 `.html` 文件（可交互查看完整图表）
- 报告生成时间：{now}
"""
    print(skeleton)


# ── 主函数 ────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="离线 benchmark 分析，输出 HTML 报告（可选 PNG）")
    parser.add_argument("--csv",        required=True,  help="benchmark 结果 CSV 路径")
    parser.add_argument("--out",        required=True,  help="输出 HTML 文件路径")
    parser.add_argument("--png-dir",    default=None,   help="PNG 导出目录（不传则跳过 PNG 导出）")
    parser.add_argument("--model-name", default="model",help="模型名称，用于 REPORT.md 骨架标题")
    args = parser.parse_args()

    csv_path = Path(args.csv)
    out_path = Path(args.out)
    png_dir  = Path(args.png_dir) if args.png_dir else None
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if png_dir:
        png_dir.mkdir(parents=True, exist_ok=True)

    print(f"[1/4] 加载 CSV: {csv_path}")
    df, err = load_exp_csv(str(csv_path))
    if err:
        print(f"❌ 加载失败: {err}")
        sys.exit(1)
    print(f"      行数: {len(df)}")

    print("[2/4] 运行分析...")
    analysis = analysis_response(df)
    metrics = analysis["metrics"]
    plots   = analysis["plots"]

    print("[3/4] 生成图表...")
    latency_dist = plots["latency distribution"]
    percentiles  = compute_percentiles(latency_dist)
    cdf_ttft    = build_cdf_figure(latency_dist["ttft"],     "TTFT")
    cdf_ttfs    = build_cdf_figure(latency_dist["ttfs"],     "TTFS")
    cdf_tpot    = build_cdf_figure(latency_dist["user_tpot"],"User-TPOT")
    cdf_e2e     = build_cdf_figure(latency_dist["e2e"],      "E2E")
    # ITL = tpot (per-token inter-token latency)，数据量 ~55 万，先降采样再绘 CDF
    itl_sampled = _downsample_for_cdf(latency_dist["tpot"], max_points=2000)
    cdf_itl     = build_cdf_figure(itl_sampled, "ITL (per-token TPOT)")

    lat_hist_fig = build_latency_hist(latency_dist)
    req_fig, thr_fig, lat_fig, sr_fig = build_timeline_figures(plots["timeline_plots"])
    tok_fig = build_token_hist(plots["token len distribution"])

    print("[4/4] 写出 HTML...")
    html_parts = [
        "<html><head><meta charset='utf-8'>"
        f"<title>分析报告 - {csv_path.stem}</title></head><body>",
        f"<h1>Benchmark 分析报告</h1>"
        f"<p>来源文件: <code>{csv_path}</code></p>"
        f"<p>生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>",
        metrics_to_html(metrics, csv_path.name, percentiles=percentiles),
        "<h2>CDF 图</h2>",
        "<p style='font-size:13px;color:#555;margin:4px 0 8px'>",
        "User-TPOT：每请求平均 TPOT（3035条）；"
        "ITL：per-token 实测间隔（55万条，已降采样至2000分位点）</p>",
        "<div style='display:flex;flex-wrap:wrap;gap:12px'>",
        pio.to_html(cdf_ttft,  full_html=False, include_plotlyjs="cdn"),
        pio.to_html(cdf_ttfs,  full_html=False, include_plotlyjs=False),
        pio.to_html(cdf_tpot,  full_html=False, include_plotlyjs=False),
        pio.to_html(cdf_itl,   full_html=False, include_plotlyjs=False),
        pio.to_html(cdf_e2e,   full_html=False, include_plotlyjs=False),
        "</div>",
        "<h2>Latency 分布（tpot / user_tpot / ttft / ttfs / e2e）</h2>",
        pio.to_html(lat_hist_fig, full_html=False, include_plotlyjs=False),
        "<h2>Timeline</h2>",
        pio.to_html(req_fig, full_html=False, include_plotlyjs=False),
        pio.to_html(thr_fig, full_html=False, include_plotlyjs=False),
        pio.to_html(lat_fig, full_html=False, include_plotlyjs=False),
        pio.to_html(sr_fig,  full_html=False, include_plotlyjs=False),
        "<h2>Token 长度分布（prompt / completion / all / first_sentence）</h2>",
        pio.to_html(tok_fig, full_html=False, include_plotlyjs=False),
        "</body></html>",
    ]

    out_path.write_text("\n".join(html_parts), encoding="utf-8")
    print(f"\n✅ HTML 报告已保存: {out_path}")
    print(f"   文件大小: {out_path.stat().st_size / 1024:.0f} KB")

    # 核心指标终端打印
    p = percentiles
    print("\n──────────── 核心指标 ────────────")
    print(f"  总请求数:     {int(metrics['all_cnt'])}")
    print(f"  成功率:       {metrics['success_rate']*100:.2f}%")
    print(f"  成功 QPS:     {metrics['success_qps']:.3f} req/s")
    print(f"  TTFT 均值:    {metrics['ttft_mean']:.3f} s")
    print(f"  TTFT P50/P90/P95/P99: {p.get('ttft_p50',0):.3f} / {p.get('ttft_p90',0):.3f} / {p.get('ttft_p95',0):.3f} / {p.get('ttft_p99',0):.3f} s")
    print(f"  TTFS 均值:    {metrics['ttfs_mean']:.3f} s  P90: {p.get('ttfs_p90',0):.3f} s")
    print(f"  E2E  均值:    {metrics['e2e_mean']:.3f} s")
    print(f"  E2E  P50/P90/P95/P99: {p.get('e2e_p50',0):.3f} / {p.get('e2e_p90',0):.3f} / {p.get('e2e_p95',0):.3f} / {p.get('e2e_p99',0):.3f} s")
    print(f"  TPOT 均值:    {metrics['tpot_mean']:.3f} s")
    print(f"  Prefill:      {metrics['prefill_throughput']:.1f} tok/s")
    print(f"  Decode:       {metrics['decode_throughput']:.1f} tok/s")
    print(f"  Overall:      {metrics['overall_throughput']:.1f} tok/s")
    print("──────────────────────────────────")

    # PNG 导出（可选）
    if png_dir:
        print(f"\n[PNG] 导出图表到 {png_dir} ...")
        export_cdf_pngs(latency_dist, png_dir)
        export_timeline_pngs(plots["timeline_plots"], png_dir)
        print_report_skeleton(metrics, png_dir, args.model_name, csv_path, percentiles=percentiles)
        print(f"\n✅ PNG 已导出，REPORT.md 骨架已打印（含 Grafana 截图提示）")


if __name__ == "__main__":
    main()
