#!/usr/bin/env python3
"""
qps-peak-finder 指标分析脚本

用途：
  Phase 0（数据集预估）：从 old_response 列预估输出 token 分布，给出 Phase 1 起始方向建议。
  Phase 1（饱和探测）：计算 decode 吞吐、输出长度分布（Avg/P50/P90/P99）、max_rps_estimate，
                       给出下一档并发数建议。
  Phase 2（自适应逼近）：计算 TTFS P90、E2E P90、SLA 状态、吞吐变化，
                         给出下一档 QPS 建议。
                         支持 --bracket-lo / --bracket-hi 区间收敛模式（几何中点精查）。
  Phase 3（上线验证网格）：汇总多档位 QPS 结果（从 token_list 反推），输出 SLA 合规表。

用法：
  # Phase 0
  python3 scripts/analysis/analyze_peak_finder.py --phase 0 --dataset datas/model.csv --tokenizer /path/tok

  # Phase 1
  python3 scripts/analysis/analyze_peak_finder.py --phase 1 --dir logs/model_phase1/con20

  # Phase 2（提供上一档目录以计算吞吐增幅；可附带 bracket 区间加速收敛）
  python3 scripts/analysis/analyze_peak_finder.py --phase 2 --dir logs/model_phase2/rps0.25 \\
      --prev-dir logs/model_phase2/rps0.23 \\
      --ttfs-p90-limit 1.5 --e2e-p90-limit 150.0 \\
      --bracket-lo 0.2369 --bracket-hi 0.2529

  # Phase 3（汇总验证网格，--dir 指向 Phase 3 根目录，含多个 qps_X.XXXX 子目录）
  python3 scripts/analysis/analyze_peak_finder.py --phase 3 --dir logs/model_phase3_grid_20260319 \\
      --ttfs-p90-limit 1.5 --e2e-p90-limit 150.0

  # 写入检查点文件（追加到 checkpoint.md）
  python3 scripts/analysis/analyze_peak_finder.py --phase 1 --dir ... --checkpoint logs/model_phase1/checkpoint.md
"""

import argparse
import sys
import glob
import json
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd

# ── 添加 llm_benchmark 到 sys.path ──────────────────────────────────────────
_PROJECT_DIR = Path(__file__).resolve().parents[2]
_LLM_BENCH_SRC = (
    _PROJECT_DIR
    / "third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/src"
)
if str(_LLM_BENCH_SRC) not in sys.path:
    sys.path.insert(0, str(_LLM_BENCH_SRC))

from llm_benchmark.analysis.analysis.single_exp import load_exp_csv, analysis_response


# ── 工具函数 ─────────────────────────────────────────────────────────────────

def find_result_csv(level_dir: Path) -> Path | None:
    """在档位目录下找到结果 CSV（排除 dataset.csv 和 .argv.csv）"""
    candidates = [
        p for p in level_dir.glob("*.csv")
        if not p.name.startswith("dataset")
        and not p.name.endswith(".argv.csv")
    ]
    if not candidates:
        return None
    return sorted(candidates)[-1]  # 取最新的


def _load_decode_throughput(level_dir: Path) -> float | None:
    """
    从档位目录读取 decode_throughput。

    优先读取 metrics_cache.json（由 analyze_phase1 写入，与 analysis_response 完全一致）；
    若无缓存则用 analysis_response 重新计算，保证与当档分析口径相同。
    """
    # 优先读缓存，避免重复加载大 CSV
    cache_path = level_dir / "metrics_cache.json"
    if cache_path.exists():
        try:
            with open(cache_path, encoding="utf-8") as f:
                cached = json.load(f)
            val = cached.get("decode_throughput")
            if val is not None and float(val) > 0:
                return float(val)
        except Exception:
            pass

    # 无缓存：用与 analyze_phase1 相同的 load_and_analyze 重新计算
    try:
        result, _ = load_and_analyze(level_dir)
        tp = result.get("metrics", {}).get("decode_throughput", 0.0)
        return float(tp) if tp > 0 else None
    except Exception as e:
        print(f"⚠️  prev-dir 吞吐计算失败 ({level_dir.name}): {e}")
        return None


def load_and_analyze(level_dir: Path):
    """加载目录下的结果 CSV 并运行 analysis_response()"""
    csv_path = find_result_csv(level_dir)
    if csv_path is None:
        print(f"❌ 在 {level_dir} 找不到结果 CSV")
        sys.exit(1)

    print(f"[分析] CSV: {csv_path.name}")
    df, err = load_exp_csv(str(csv_path))
    if err:
        print(f"⚠️  加载警告: {err}")
    if df is None:
        print("❌ CSV 加载失败")
        sys.exit(1)

    result = analysis_response(df)
    return result, csv_path


def calc_max_active_requests(df_ok: pd.DataFrame) -> int:
    """从 start_time/end_time 重建并发曲线，返回峰值并发数"""
    events = []
    for _, row in df_ok.iterrows():
        events.append((row["start_time"], +1))
        events.append((row["end_time"],   -1))
    events.sort(key=lambda x: x[0])

    peak, cur = 0, 0
    for _, delta in events:
        cur += delta
        if cur > peak:
            peak = cur
    return peak


# ── Phase 1 分析 ─────────────────────────────────────────────────────────────

def analyze_phase1(level_dir: Path, prev_throughput: float | None,
                   checkpoint_path: Path | None):
    print("\n" + "=" * 60)
    print(f"Phase 1 饱和探测分析  ← {level_dir.name}")
    print("=" * 60)

    result, csv_path = load_and_analyze(level_dir)
    metrics = result.get("metrics", {})
    df_ok: pd.DataFrame = result.get("df_analysis")

    if df_ok is None or len(df_ok) == 0:
        print("❌ 无有效数据行，请检查 CSV 内容")
        sys.exit(1)

    # ── 输出长度分布 ────────────────────────────────────────────────────────
    if "completion_token_cnt" not in df_ok.columns:
        print("⚠️  completion_token_cnt 列不存在（未提供 tokenizer？），无法计算输出分布")
        avg_output_len = None
    else:
        comp = df_ok["completion_token_cnt"].dropna()
        avg_output_len = comp.mean()
        print("\n── 输出长度分布（completion tokens）──")
        print(f"  Avg : {avg_output_len:>8.1f} tokens")
        print(f"  P50 : {comp.quantile(0.50):>8.1f} tokens")
        print(f"  P90 : {comp.quantile(0.90):>8.1f} tokens")
        print(f"  P99 : {comp.quantile(0.99):>8.1f} tokens")
        print(f"  样本数: {len(comp)}")

    # ── 吞吐指标 ────────────────────────────────────────────────────────────
    decode_tp  = metrics.get("decode_throughput", 0.0)
    total_dur  = metrics.get("total_duration",    0.0)
    success_rate = metrics.get("success_rate",    0.0)
    all_cnt    = metrics.get("all_cnt",            0)
    success_cnt = metrics.get("success_count",     0)

    print("\n── 吞吐与请求统计 ──")
    print(f"  decode_throughput : {decode_tp:.3f} tokens/s")
    print(f"  prefill_throughput: {metrics.get('prefill_throughput', 0):.3f} tokens/s")
    print(f"  总时长            : {total_dur:.1f}s")
    print(f"  发送请求数        : {all_cnt}")
    print(f"  成功请求数        : {success_cnt}  ({success_rate*100:.1f}%)")

    # ── max_rps_estimate ────────────────────────────────────────────────────
    if avg_output_len and avg_output_len > 0:
        max_rps = decode_tp / avg_output_len
        print(f"\n── 换算极限 RPS ──")
        print(f"  max_rps_estimate = {decode_tp:.3f} / {avg_output_len:.1f} = {max_rps:.4f} req/s")
        print(f"  Phase 2 建议起始 QPS = {max_rps * 1.2:.4f} req/s  (× 1.2)")
    else:
        max_rps = None

    # ── 峰值并发 ────────────────────────────────────────────────────────────
    peak_concur = calc_max_active_requests(df_ok)
    print(f"  max_active_requests (峰值并发) = {peak_concur}")

    # ── 饱和判断 ────────────────────────────────────────────────────────────
    print("\n── 饱和判断 ──")
    try:
        concurrency = int(level_dir.name.replace("con", ""))
    except ValueError:
        concurrency = 0  # 非标准目录名（如用历史 qps_* 目录测试时）

    if prev_throughput is not None and prev_throughput > 0:
        growth_pct = (decode_tp - prev_throughput) / prev_throughput * 100
        print(f"  上档吞吐: {prev_throughput:.3f} tokens/s")
        print(f"  本档吞吐: {decode_tp:.3f} tokens/s")
        print(f"  增幅:     {growth_pct:+.2f}%")

        if growth_pct < 1.0:
            verdict = "✅ 已饱和"
            next_con = None
            advice = "停止 Phase 1，进入 Phase 2"
        elif growth_pct <= 10.0:
            verdict = "🔶 接近饱和"
            next_con = concurrency + 10
            advice = f"线性 +10 → 下一档并发: {next_con}"
        else:
            verdict = "🔴 未饱和"
            next_con = concurrency * 2
            advice = f"翻倍 ×2 → 下一档并发: {next_con}"

        print(f"  结论: {verdict}")
        print(f"  建议: {advice}")
        # 机器可读 tag，供 Phase 1 自动循环脚本解析
        if next_con is None:
            print("[NEXT_CON=SATURATED]")
        else:
            print(f"[NEXT_CON={next_con}]")
    else:
        print("  （首档，无上档对比）")
        next_con = concurrency * 2
        print(f"  建议下一档并发: {next_con}（翻倍）")
        print(f"[NEXT_CON={next_con}]")

    # ── 写入 metrics_cache.json（供下一档 _load_decode_throughput 使用）──────
    cache_path = level_dir / "metrics_cache.json"
    try:
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump({"decode_throughput": decode_tp}, f)
    except Exception:
        pass

    # ── 检查点写入 ──────────────────────────────────────────────────────────
    if checkpoint_path:
        _write_phase1_checkpoint(
            checkpoint_path, level_dir.name, concurrency,
            decode_tp, prev_throughput, avg_output_len,
            max_rps, peak_concur
        )

    print("")


def _write_phase1_checkpoint(path: Path, level_name: str, concurrency: int,
                              decode_tp: float, prev_tp: float | None,
                              avg_output_len: float | None,
                              max_rps: float | None, peak_concur: int):
    growth_str = ""
    if prev_tp is not None and prev_tp > 0:
        g = (decode_tp - prev_tp) / prev_tp * 100
        growth_str = f"{g:+.2f}%"

    lines = [
        f"\n## Phase 1 检查点 — {level_name}  ({datetime.now().strftime('%Y-%m-%d %H:%M')})\n",
        f"| 指标 | 值 |",
        f"|------|-----|",
        f"| 并发数 | {concurrency} |",
        f"| decode_throughput | {decode_tp:.3f} tokens/s |",
        f"| 上档吞吐增幅 | {growth_str or '—'} |",
        f"| avg_output_len | {f'{avg_output_len:.1f} tokens' if avg_output_len else '—'} |",
        f"| max_rps_estimate | {f'{max_rps:.4f} req/s' if max_rps else '—'} |",
        f"| max_active_requests | {peak_concur} |",
        f"\n如有调整意见请在此回复 ↓\n",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"[检查点] 已追加写入: {path}")


# ── Phase 2 分析 ─────────────────────────────────────────────────────────────

def analyze_phase2(level_dir: Path, prev_dir: Path | None,
                   ttfs_limit: float, e2e_limit: float,
                   checkpoint_path: Path | None,
                   extra_sla: list[dict] | None,
                   args_peak_rps: float | None = None,
                   args_bracket_lo: float | None = None,
                   args_bracket_hi: float | None = None):
    print("\n" + "=" * 60)
    print(f"Phase 2 自适应探测分析  ← {level_dir.name}")
    print("=" * 60)

    result, csv_path = load_and_analyze(level_dir)
    metrics = result.get("metrics", {})
    df_ok: pd.DataFrame = result.get("df_analysis")

    if df_ok is None or len(df_ok) == 0:
        print("❌ 无有效数据行，请检查 CSV 内容")
        sys.exit(1)

    # ── 输出长度分布 ────────────────────────────────────────────────────────
    if "completion_token_cnt" in df_ok.columns:
        comp = df_ok["completion_token_cnt"].dropna()
        avg_output_len = comp.mean()
        print("\n── 输出长度分布 ──")
        print(f"  Avg: {avg_output_len:.1f}  P50: {comp.quantile(0.5):.1f}"
              f"  P90: {comp.quantile(0.9):.1f}  P99: {comp.quantile(0.99):.1f}  (tokens)")
    else:
        avg_output_len = None

    # ── 延迟指标 ────────────────────────────────────────────────────────────
    decode_tp   = metrics.get("decode_throughput", 0.0)
    success_rate = metrics.get("success_rate",     0.0)
    all_cnt     = metrics.get("all_cnt",            0)

    ttfs_p90 = df_ok["ttfs"].quantile(0.90) if "ttfs" in df_ok.columns else None
    e2e_p90  = df_ok["e2e"].quantile(0.90)  if "e2e"  in df_ok.columns else None
    ttft_p90 = df_ok["ttft"].quantile(0.90) if "ttft" in df_ok.columns else None

    peak_concur = calc_max_active_requests(df_ok)
    rps_tag = level_dir.name.replace("rps", "")
    try:
        current_rps = float(rps_tag)
    except ValueError:
        current_rps = 0.0

    print("\n── 延迟指标 ──")
    print(f"  TTFT P90 : {ttft_p90*1000:.0f} ms" if ttft_p90 is not None else "  TTFT P90 : —")
    print(f"  TTFS P90 : {ttfs_p90*1000:.0f} ms  (限: {ttfs_limit*1000:.0f} ms)" if ttfs_p90 is not None else "  TTFS P90 : —")
    print(f"  E2E  P90 : {e2e_p90:.2f} s       (限: {e2e_limit:.1f} s)" if e2e_p90 is not None else "  E2E  P90 : —")

    print("\n── 吞吐与请求统计 ──")
    print(f"  decode_throughput   : {decode_tp:.3f} tokens/s")
    print(f"  max_active_requests : {peak_concur}")
    print(f"  发送请求数          : {all_cnt}  成功率: {success_rate*100:.1f}%")

    # ── SLA 评估 ────────────────────────────────────────────────────────────
    sla_failures = []
    if ttfs_p90 is not None and ttfs_p90 > ttfs_limit:
        sla_failures.append(f"TTFS P90 {ttfs_p90*1000:.0f}ms > {ttfs_limit*1000:.0f}ms")
    if e2e_p90 is not None and e2e_p90 > e2e_limit:
        sla_failures.append(f"E2E P90 {e2e_p90:.2f}s > {e2e_limit:.1f}s")
    if extra_sla:
        for rule in extra_sla:
            col = f"{rule['metric']}_p{rule['percentile']}" if rule['metric'] != 'e2e' else 'e2e'
            val_col = "e2e" if rule["metric"] == "e2e" else rule["metric"]
            if val_col in df_ok.columns:
                val = df_ok[val_col].quantile(rule["percentile"] / 100)
                if val > rule["limit"]:
                    sla_failures.append(f"{rule.get('label', val_col)} {val:.3f} > {rule['limit']}")

    sla_ok = len(sla_failures) == 0
    print(f"\n── SLA 评估 ──")
    if sla_ok:
        print("  ✅ 通过")
    else:
        print("  ❌ 不通过")
        for f in sla_failures:
            print(f"     ✗ {f}")

    # ── 吞吐对比（与上档）────────────────────────────────────────────────────
    prev_decode_tp = None
    if prev_dir is not None:
        prev_decode_tp = _load_decode_throughput(prev_dir)
        growth_pct = (decode_tp - prev_decode_tp) / prev_decode_tp * 100 if prev_decode_tp > 0 else 0
        print(f"\n── 吞吐对比 ──")
        print(f"  上档: {prev_decode_tp:.3f} tokens/s → 本档: {decode_tp:.3f} tokens/s  ({growth_pct:+.2f}%)")
    else:
        growth_pct = None

    # ── 综合决策建议（Phase 2a 两阶段：比例快速逼近 + 区间几何中点精查）────────
    # 阶段 1（无区间）：比例步进，渐近边界
    #   SLA 失败 → next = current × (1/worst_ratio)^0.8
    #   SLA 通过 → next = current × (1/worst_ratio)^0.6，裕量 <5% 即收敛
    #   首档超载（current > peak_rps）→ 直接跳到 peak_rps × 0.8
    #
    # 阶段 2（已有 bracket lo+hi）：几何中点精查
    #   next = sqrt(lo * hi)
    #   bracket_width = (hi - lo)/lo < 3% → 收敛，ideal_rps = lo
    #
    # Shell 可解析标记（输出到 stdout）：
    #   [SLA_PASS]   / [SLA_FAIL]    → 供 auto 脚本更新 bracket
    #   [NEXT_RPS=X] → 供 auto 脚本提取下一档

    peak_rps = args_peak_rps

    # 计算最差比值（actual/limit）：>1 超标，<1 有裕量，始终从 0 开始取所有指标的最大值
    worst_ratio = 0.0
    if e2e_p90 is not None:
        worst_ratio = max(worst_ratio, e2e_p90 / e2e_limit)
    if ttfs_p90 is not None:
        worst_ratio = max(worst_ratio, ttfs_p90 / ttfs_limit)
    if extra_sla:
        for rule in extra_sla:
            val_col = "e2e" if rule["metric"] == "e2e" else rule["metric"]
            if val_col in df_ok.columns:
                val = df_ok[val_col].quantile(rule["percentile"] / 100)
                worst_ratio = max(worst_ratio, val / rule["limit"])
    if worst_ratio == 0.0:
        worst_ratio = 1.0

    # 输出 SLA 机器可读标记
    print(f"\n[SLA_{'PASS' if sla_ok else 'FAIL'}]")

    print("\n── 决策建议 ──")

    bracket_lo = args_bracket_lo
    bracket_hi = args_bracket_hi

    # 优先用区间精查（bracket 阶段 2）
    if bracket_lo is not None and bracket_hi is not None:
        bracket_width = (bracket_hi - bracket_lo) / bracket_lo
        print(f"  📐 已知区间: [{bracket_lo:.4f}, {bracket_hi:.4f}]  宽度: {bracket_width*100:.1f}%")
        if bracket_width < 0.03:
            print(f"  ✅ 区间宽度 < 3% → 已收敛")
            print(f"  🎯 ideal_rps = {bracket_lo:.4f} req/s  (bracket lo)")
            next_rps = None
        else:
            next_rps = round(float(np.sqrt(bracket_lo * bracket_hi)), 4)
            print(f"  → 几何中点: sqrt({bracket_lo:.4f} × {bracket_hi:.4f}) = {next_rps:.4f} req/s")
    else:
        # 无区间：比例步进（阶段 1）
        is_overloaded = (peak_rps is not None and current_rps > peak_rps)
        is_first_probe = (prev_dir is None)

        if not sla_ok:
            overshoot_pct = (worst_ratio - 1) * 100
            if is_first_probe and is_overloaded:
                next_rps = round(peak_rps * 0.8, 4)
                print(f"  ⚡ 首档超载（ρ={current_rps/peak_rps:.2f}），直接跳到安全区")
                print(f"     next = peak_rps × 0.8 = {peak_rps:.4f} × 0.8 = {next_rps:.4f} req/s")
            else:
                next_rps = round(current_rps * (1.0 / worst_ratio) ** 0.8, 4)
                print(f"  ❌ SLA 不通过（超标 {overshoot_pct:.0f}%）")
                print(f"     next = {current_rps:.4f} × (1/{worst_ratio:.3f})^0.8 = {next_rps:.4f} req/s")
        else:
            slack_pct = (1.0 / worst_ratio - 1) * 100 if worst_ratio < 1.0 else 0.0
            if slack_pct < 5.0:
                print(f"  ✅ SLA 通过，裕量仅 {slack_pct:.1f}% → 已收敛（建议开启 bracket 精查）")
                print(f"  🎯 ideal_rps ≈ {current_rps:.4f} req/s")
                next_rps = None
            elif slack_pct < 20.0:
                step = (1.0 / worst_ratio) ** 0.6
                next_rps = round(current_rps * step, 4)
                print(f"  ✅ SLA 通过，裕量 {slack_pct:.1f}%（小步上探）")
                print(f"     next = {current_rps:.4f} × (1/{worst_ratio:.3f})^0.6 = {next_rps:.4f} req/s")
            else:
                step = min((1.0 / worst_ratio) ** 0.6, 1.25)
                next_rps = round(current_rps * step, 4)
                print(f"  ✅ SLA 通过，裕量 {slack_pct:.1f}%（大步上探）")
                print(f"     next = {current_rps:.4f} × {step:.3f} = {next_rps:.4f} req/s")

    if next_rps is not None:
        print(f"  → 下一档 QPS：{next_rps:.4f}")
        print(f"[NEXT_RPS={next_rps:.4f}]")
    else:
        print("[NEXT_RPS=CONVERGED]")

    # ── 检查点写入 ──────────────────────────────────────────────────────────
    if checkpoint_path:
        _write_phase2_checkpoint(
            checkpoint_path, level_dir.name, current_rps,
            decode_tp, prev_decode_tp, peak_concur,
            ttfs_p90, e2e_p90, sla_ok, sla_failures
        )

    print("")


def _write_phase2_checkpoint(path: Path, level_name: str, current_rps: float,
                              decode_tp: float, prev_tp: float | None,
                              peak_concur: int, ttfs_p90: float | None,
                              e2e_p90: float | None, sla_ok: bool,
                              sla_failures: list[str]):
    growth_str = ""
    if prev_tp is not None and prev_tp > 0:
        g = (decode_tp - prev_tp) / prev_tp * 100
        growth_str = f"{g:+.2f}%"

    ttfs_str = f"{ttfs_p90*1000:.0f} ms" if ttfs_p90 is not None else "—"
    e2e_str  = f"{e2e_p90:.2f} s"         if e2e_p90  is not None else "—"
    sla_str  = "✅" if sla_ok else f"❌ {'; '.join(sla_failures)}"

    lines = [
        f"\n## Phase 2 检查点 — {level_name}  ({datetime.now().strftime('%Y-%m-%d %H:%M')})\n",
        f"| 指标 | 本档 | 上档 | 变化 |",
        f"|------|------|------|------|",
        f"| decode_throughput | {decode_tp:.3f} tokens/s | {f'{prev_tp:.3f}' if prev_tp else '—'} | {growth_str or '—'} |",
        f"| max_active_requests | {peak_concur} | — | — |",
        f"| TTFS P90 | {ttfs_str} | — | — |",
        f"| E2E P90 | {e2e_str} | — | — |",
        f"| SLA | {sla_str} | — | — |",
        f"\n如有调整意见请在此回复 ↓\n",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"[检查点] 已追加写入: {path}")


# ── CLI ──────────────────────────────────────────────────────────────────────

def analyze_dataset(dataset_path: Path, tokenizer_path: str | None):
    """
    从数据集 CSV 的 old_response 列预估输出长度分布。
    不需要跑任何 benchmark，用于 Phase 1 前预估 max_rps_estimate。
    """
    print("\n" + "=" * 60)
    print(f"数据集输出长度预估  ← {dataset_path.name}")
    print("=" * 60)

    df = pd.read_csv(dataset_path, dtype={"old_response": str})
    df["old_response"] = df["old_response"].fillna("")
    df_has_resp = df[df["old_response"].str.len() > 0]
    total = len(df)
    valid = len(df_has_resp)
    print(f"  总行数: {total}  含 old_response: {valid}  ({valid/total*100:.1f}%)")

    if valid == 0:
        print("  ⚠️  old_response 列为空，无法估算输出长度")
        return

    # ── 字符数分布（无需 tokenizer）──────────────────────────────────────────
    char_lens = df_has_resp["old_response"].str.len()
    print(f"\n── 输出长度分布（字符数，近似参考）──")
    print(f"  Avg : {char_lens.mean():>8.1f} chars")
    print(f"  P50 : {char_lens.quantile(0.50):>8.1f} chars")
    print(f"  P90 : {char_lens.quantile(0.90):>8.1f} chars")
    print(f"  P99 : {char_lens.quantile(0.99):>8.1f} chars")

    # ── Token 数分布（需要 tokenizer）────────────────────────────────────────
    if tokenizer_path:
        print(f"\n  正在加载 tokenizer: {tokenizer_path} ...")
        try:
            from transformers import AutoTokenizer
            import os
            os.environ["TOKENIZERS_PARALLELISM"] = "false"
            tok = AutoTokenizer.from_pretrained(tokenizer_path)
            sample = df_has_resp["old_response"].head(500)  # 最多采样 500 条
            token_lens = sample.apply(lambda x: len(tok.encode(x, add_special_tokens=False)))
            avg_tokens = token_lens.mean()
            print(f"\n── 输出长度分布（tokens，采样 {len(sample)} 条）──")
            print(f"  Avg : {avg_tokens:>8.1f} tokens  ← 推荐用于换算 max_rps_estimate")
            print(f"  P50 : {token_lens.quantile(0.50):>8.1f} tokens")
            print(f"  P90 : {token_lens.quantile(0.90):>8.1f} tokens")
            print(f"  P99 : {token_lens.quantile(0.99):>8.1f} tokens")
            print(f"\n  💡 示例：若 peak_decode_throughput = X tokens/s")
            print(f"     max_rps_estimate = X / {avg_tokens:.1f} req/s")
        except Exception as e:
            print(f"  ⚠️  tokenizer 加载失败: {e}")
            print(f"  退而使用字符数 ÷ 3.5 粗估（中文模型经验值）")
            avg_tokens = char_lens.mean() / 3.5
            print(f"  粗估 avg_tokens ≈ {avg_tokens:.1f}")
    else:
        avg_tokens = char_lens.mean() / 3.5
        print(f"\n  （未提供 tokenizer，字符数 ÷ 3.5 粗估 avg_tokens ≈ {avg_tokens:.1f}）")

    # ── Phase 1 起始方向建议（基于输出长度先验）────────────────────────────
    print(f"\n── Phase 1 起始方向建议 ──")
    avg_for_advice = avg_tokens if tokenizer_path else (char_lens.mean() / 3.5)
    if avg_for_advice < 200:
        start_dir = "从高并发向下"
        start_con = 200
        reason = f"短输出（avg≈{avg_for_advice:.0f} tokens），快进快出，最优并发高，从高向低更快找拐点"
    elif avg_for_advice < 600:
        start_dir = "从中等并发向上"
        start_con = 50
        reason = f"中等输出（avg≈{avg_for_advice:.0f} tokens），从 50 翻倍向上探"
    elif avg_for_advice < 1500:
        start_dir = "从低并发向上"
        start_con = 20
        reason = f"较长输出（avg≈{avg_for_advice:.0f} tokens），最优并发中等，从 20 翻倍向上探"
    else:
        start_dir = "从低并发向上"
        start_con = 10
        reason = f"超长推理输出（avg≈{avg_for_advice:.0f} tokens），E2E 耗时大，最优并发低，从 10 翻倍向上探"
    print(f"  策略: {start_dir}  建议起始并发: con={start_con}")
    print(f"  原因: {reason}")
    print(f"\n  Phase 2 建议起始 QPS：待 Phase 1 完成后由 peak_throughput / avg_tokens 计算")
    print("")


def _parse_token_list_metrics(csv_path: Path) -> pd.DataFrame | None:
    """
    从结果 CSV 的 token_list 列反推每请求的 start_ts/end_ts/tok_cnt/ttfs_ms/e2e_s。
    用于 Phase 3 汇总和缺少 start_time/end_time 字段的旧格式 CSV。
    """
    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        print(f"⚠️  CSV 读取失败: {e}")
        return None

    tl_col = None
    for col in ["token_list", "token_lists"]:
        if col in df.columns:
            tl_col = col
            break
    if tl_col is None:
        return None

    rows = []
    for _, row in df.iterrows():
        tl_raw = row.get(tl_col, "")
        if not isinstance(tl_raw, str) or not tl_raw.strip():
            continue
        try:
            tl = json.loads(tl_raw)
            if len(tl) < 2:
                continue
            start_ts = tl[0]["timestamp"]
            end_ts   = tl[-1]["timestamp"]
            tok_cnt  = max(0, len(tl) - 2)
            ttfs_ms  = (tl[1]["timestamp"] - tl[0]["timestamp"]) * 1000
            e2e_s    = end_ts - start_ts
            rows.append({"start_ts": start_ts, "end_ts": end_ts,
                         "tok_cnt": tok_cnt, "ttfs_ms": ttfs_ms, "e2e_s": e2e_s})
        except Exception:
            continue

    if not rows:
        return None
    return pd.DataFrame(rows)


def analyze_phase3(base_dir: Path, ttfs_limit: float, e2e_limit: float,
                   checkpoint_path: Path | None):
    """
    Phase 3 上线验证网格汇总：
    遍历 base_dir 下的 qps_X.XXXX 子目录，从 token_list 反推指标，输出汇总表。
    """
    print("\n" + "=" * 60)
    print(f"Phase 3 上线验证网格汇总  ← {base_dir.name}")
    print("=" * 60)

    qps_dirs = sorted(
        [d for d in base_dir.iterdir() if d.is_dir() and d.name.startswith("qps_")]
    )
    if not qps_dirs:
        print(f"❌ {base_dir} 下未找到 qps_X.XXXX 子目录")
        return

    rows_summary = []
    for qps_dir in qps_dirs:
        csvs = [f for f in qps_dir.glob("*.csv") if "argv" not in f.name]
        if not csvs:
            print(f"  ⚠️  {qps_dir.name}: 无 CSV，跳过")
            continue
        csv_path = sorted(csvs)[-1]
        parsed = _parse_token_list_metrics(csv_path)
        if parsed is None or parsed.empty:
            print(f"  ⚠️  {qps_dir.name}: token_list 解析失败，跳过")
            continue

        dur = parsed["end_ts"].max() - parsed["start_ts"].min()
        thp = parsed["tok_cnt"].sum() / dur if dur > 0 else 0.0
        ttfs_p90 = parsed["ttfs_ms"].quantile(0.9)
        ttfs_p50 = parsed["ttfs_ms"].quantile(0.5)
        e2e_p90  = parsed["e2e_s"].quantile(0.9)
        e2e_p50  = parsed["e2e_s"].quantile(0.5)
        n = len(parsed)

        sla_ok = (ttfs_p90 <= ttfs_limit * 1000) and (e2e_p90 <= e2e_limit)
        rows_summary.append({
            "档位": qps_dir.name,
            "decode(t/s)": round(thp, 1),
            "TTFS_P50(ms)": round(ttfs_p50, 0),
            "TTFS_P90(ms)": round(ttfs_p90, 0),
            "E2E_P50(s)":   round(e2e_p50, 1),
            "E2E_P90(s)":   round(e2e_p90, 1),
            "n": n,
            "SLA": "✅" if sla_ok else "❌",
        })

    if not rows_summary:
        print("❌ 所有档位均无可用数据")
        return

    # 打印汇总表
    df_sum = pd.DataFrame(rows_summary)
    print()
    print(df_sum.to_string(index=False))
    print()

    all_pass = all(r["SLA"] == "✅" for r in rows_summary)
    if all_pass:
        print("✅ 所有档位 SLA 全部通过，上线验证完成")
    else:
        fail_levels = [r["档位"] for r in rows_summary if r["SLA"] == "❌"]
        print(f"⚠️  以下档位 SLA 不通过: {', '.join(fail_levels)}")
        print("   请检查 ideal_rps 是否被高估")

    # 稳定性简检：E2E P50 是否单调递增（吻合正常负载曲线）
    e2e_p50_vals = [r["E2E_P50(s)"] for r in rows_summary]
    is_monotone = all(e2e_p50_vals[i] <= e2e_p50_vals[i+1] for i in range(len(e2e_p50_vals)-1))
    print(f"\n── 曲线单调性检查（E2E P50 随 QPS 递增）──")
    if is_monotone:
        print("  ✅ E2E P50 单调递增，延迟曲线走势正常")
    else:
        print("  ⚠️  E2E P50 非单调，可能存在测量噪声或服务抖动，建议检查各档位日志")

    # 检查点写入
    if checkpoint_path:
        checkpoint_path.parent.mkdir(parents=True, exist_ok=True)
        with open(checkpoint_path, "a", encoding="utf-8") as f:
            f.write(f"\n## Phase 3 汇总 ({datetime.now().strftime('%Y-%m-%d %H:%M')})\n\n")
            f.write(df_sum.to_markdown(index=False))
            f.write(f"\n\nSLA全部通过: {'✅' if all_pass else '❌'}  "
                    f"E2E P50 单调: {'✅' if is_monotone else '⚠️'}\n")
        print(f"[检查点] 已追加写入: {checkpoint_path}")


def main():
    parser = argparse.ArgumentParser(description="qps-peak-finder 指标分析脚本")
    parser.add_argument("--phase", type=int, choices=[0, 1, 2, 3],
                        help="分析阶段：0=数据集预估，1=饱和探测，2=自适应逼近，3=上线验证网格汇总")
    parser.add_argument("--dir",      default=None,
                        help="本档结果目录（含 *.csv）")
    parser.add_argument("--prev-dir", default=None,
                        help="上一档结果目录（用于计算吞吐增幅，Phase 1/2 均支持）")
    parser.add_argument("--checkpoint", default=None,
                        help="检查点文件路径（追加写入 Markdown）")
    # Phase 0 专用
    parser.add_argument("--dataset", default=None,
                        help="[Phase 0] 数据集 CSV 路径，从 old_response 预估输出长度分布")
    parser.add_argument("--tokenizer", default=None,
                        help="[Phase 0] tokenizer 路径，用于精确计算 token 数")
    # Phase 2 SLA 参数
    parser.add_argument("--ttfs-p90-limit", type=float, default=1.5,
                        help="TTFS P90 上限（秒，默认 1.5）")
    parser.add_argument("--e2e-p90-limit",  type=float, default=150.0,
                        help="E2E P90 上限（秒，默认 150.0）")
    parser.add_argument("--extra-sla", type=str, default=None,
                        help='额外 SLA 规则 JSON，如 \'[{"metric":"e2e","percentile":95,"limit":0.4,"label":"tianji E2E P95"}]\'')
    parser.add_argument("--peak-rps", type=float, default=None,
                        help="Phase 1 得到的 peak_rps（极限 RPS），用于判断系统是否超载（Phase 2 决策）")
    parser.add_argument("--bracket-lo", type=float, default=None,
                        help="[Phase 2] 已知最高通过 RPS（bracket 下界），启用区间几何中点精查")
    parser.add_argument("--bracket-hi", type=float, default=None,
                        help="[Phase 2] 已知最低失败 RPS（bracket 上界），与 --bracket-lo 配合使用")
    args = parser.parse_args()

    extra_sla = json.loads(args.extra_sla) if args.extra_sla else None
    checkpoint = Path(args.checkpoint) if args.checkpoint else None

    # ── Phase 0：数据集预估（无需跑 benchmark）───────────────────────────────
    if args.phase == 0:
        if not args.dataset:
            print("❌ --phase 0 需要提供 --dataset 路径")
            sys.exit(1)
        analyze_dataset(Path(args.dataset), args.tokenizer)
        return

    # ── Phase 1 / 2：需要 --dir ──────────────────────────────────────────────
    if not args.dir:
        print("❌ --phase 1/2 需要提供 --dir 路径")
        sys.exit(1)

    level_dir = Path(args.dir)
    if not level_dir.exists():
        print(f"❌ 目录不存在: {level_dir}")
        sys.exit(1)

    prev_dir = Path(args.prev_dir) if args.prev_dir else None

    # ── Phase 3：上线验证网格汇总 ────────────────────────────────────────────
    if args.phase == 3:
        analyze_phase3(level_dir, args.ttfs_p90_limit, args.e2e_p90_limit, checkpoint)
        return

    if args.phase == 1:
        prev_throughput = None
        if prev_dir is not None:
            prev_throughput = _load_decode_throughput(prev_dir)
        analyze_phase1(level_dir, prev_throughput, checkpoint)
    else:
        analyze_phase2(level_dir, prev_dir,
                       args.ttfs_p90_limit, args.e2e_p90_limit,
                       checkpoint, extra_sla,
                       args_peak_rps=args.peak_rps,
                       args_bracket_lo=args.bracket_lo,
                       args_bracket_hi=args.bracket_hi)


if __name__ == "__main__":
    main()
