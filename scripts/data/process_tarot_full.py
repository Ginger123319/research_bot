#!/usr/bin/env python3
"""
xinghan-tarot-72b-agentv1 数据处理脚本

源数据: /mnt/ai-infra/datasets/used4evaluation/xinghan-tarot-72b-agentv1/by_day/
       已包含全量日期分片 CSV（income_time, prompt, messages, old_response）
       Steps 1+1.5 已完成，本脚本从 Step 2（峰值采样）开始执行。

管道:
  Step 2: 峰值窗口采样（凌晨 00:00~00:30，3 天峰值）
  Step 3: 时间戳拼接（消除段间大间隔）
  Step 4: DataInterpolator 泊松插值 → _poisson_{TARGET_RPM}_stitched.csv
  Step 5: 脏数据过滤（messages content 为 list 的行）
  Step 6: 写 README.md

峰值分析（全局 Top RPM）:
  2025-08-16 00:01 → 971 RPM
  2025-08-12 00:01 → 953 RPM
  2025-08-04 00:02 → 946 RPM
"""

import sys
import os
import json
import pandas as pd
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "third_party/data_analysis"))

# ============================================================
# 配置
# ============================================================
BY_DAY_DIR  = "/mnt/ai-infra/datasets/used4evaluation/xinghan-tarot-72b-agentv1/by_day"
OUTPUT_DIR  = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output_tarot"
MODEL_NAME  = "xinghan-tarot-72b-agentv1"
TARGET_RPM  = 120    # 单实例 demo 测试目标 RPM（自然低峰期 avg ~82 RPM，峰值 ~117 RPM，插值至 120 RPM）
SEG_GAP     = pd.Timedelta("5min")   # 段间间隔阈值

# 峰值时间窗口（低峰期 04:00~05:00，avg ~82 RPM，peak ~117 RPM，适合单实例测试）
# 凌晨峰值（00:00~00:30）约 800-970 RPM 为全服务总负载，不适合单实例测试
PEAK_WINDOWS = [
    ("2025-08-04 04:00:00", "2025-08-04 05:00:00", "08-04 低峰期 avg ~82 RPM"),
    ("2025-08-12 04:00:00", "2025-08-12 05:00:00", "08-12 低峰期 avg ~82 RPM"),
    ("2025-08-16 04:00:00", "2025-08-16 05:00:00", "08-16 低峰期 avg ~82 RPM"),
]

os.makedirs(OUTPUT_DIR, exist_ok=True)

print("=" * 60)
print("xinghan-tarot-72b-agentv1 数据处理（Step 2~6）")
print("=" * 60)
print(f"  源目录:   {BY_DAY_DIR}")
print(f"  输出目录: {OUTPUT_DIR}")
print(f"  目标 RPM: {TARGET_RPM} RPM（单实例 demo 测试）")
print(f"  峰值窗口: {len(PEAK_WINDOWS)} 段（凌晨高峰）")
print()

# ============================================================
# Step 2：峰值窗口采样
# ============================================================
combined_csv = Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_lowpeak.csv"

if combined_csv.exists():
    print(f"Step 2: 检测到已有峰值采样文件，直接加载 {combined_csv.name}")
    df_combined = pd.read_csv(combined_csv)
    df_combined["income_time"] = pd.to_datetime(df_combined["income_time"])
else:
    print("Step 2: 峰值窗口采样")
    print("-" * 40)

    sampled_frames = []
    for start_str, end_str, desc in PEAK_WINDOWS:
        day_str = start_str[:10]
        day_csv = Path(BY_DAY_DIR) / f"{MODEL_NAME}_{day_str}.csv"

        if not day_csv.exists():
            print(f"  ⚠️  找不到 {day_csv.name}，跳过")
            continue

        print(f"  读取 {day_csv.name} ...")
        df_day = pd.read_csv(day_csv, dtype={"prompt": str, "messages": str, "old_response": str})
        df_day["income_time"] = pd.to_datetime(df_day["income_time"])

        mask = (df_day["income_time"] >= start_str) & (df_day["income_time"] < end_str)
        df_win = df_day[mask].copy().reset_index(drop=True)

        if len(df_win) == 0:
            print(f"  ⚠️  {desc}: 无数据")
            continue

        peak_rpm = df_win["income_time"].dt.floor("1min").value_counts().max()
        print(f"  ✅ {desc}: {len(df_win):,} 条，峰值 {peak_rpm} RPM")
        sampled_frames.append(df_win)

    if not sampled_frames:
        print("❌ 未采到任何峰值数据，退出")
        sys.exit(1)

    df_combined = pd.concat(sampled_frames, ignore_index=True).sort_values("income_time").reset_index(drop=True)
    print(f"\n  合计: {len(df_combined):,} 条")
    df_combined.to_csv(combined_csv, index=False)
    print(f"  → {combined_csv.name}\n")

# ============================================================
# Step 3：时间戳拼接（消除段间大间隔）
# ============================================================
stitched_csv = Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_lowpeak_stitched.csv"

if stitched_csv.exists():
    print(f"Step 3: 检测到已有拼接文件，跳过 {stitched_csv.name}")
    df_stitched = pd.read_csv(stitched_csv)
else:
    print("Step 3: 时间戳拼接（消除段间大间隔）")
    print("-" * 40)

    df_stitched = df_combined.copy()
    df_stitched = df_stitched.sort_values("income_time").reset_index(drop=True)

    # 找段间大于 SEG_GAP 的分割点，逐段拼接
    times = df_stitched["income_time"]
    deltas = times.diff()
    big_gaps = deltas[deltas > SEG_GAP].index.tolist()

    print(f"  发现 {len(big_gaps)} 个大间隔（>{SEG_GAP}），执行拼接...")
    adjusted = times.copy()
    for gap_idx in big_gaps:
        # 计算该间隔需要压缩的时间量
        real_gap = deltas[gap_idx]
        min_gap = pd.Timedelta("1s")   # 替换为 1s 间隔
        shift = real_gap - min_gap
        # 将该点及之后所有时间戳前移 shift
        adjusted.iloc[gap_idx:] -= shift

    df_stitched["income_time"] = adjusted
    total_span = (df_stitched["income_time"].iloc[-1] - df_stitched["income_time"].iloc[0]).total_seconds() / 60
    print(f"  拼接后时间跨度: {total_span:.1f} 分钟，{len(df_stitched):,} 条")

    df_stitched.to_csv(stitched_csv, index=False)
    print(f"  → {stitched_csv.name}\n")

# ============================================================
# Step 4：泊松插值（放大至 TARGET_RPM）
# ============================================================
poisson_csv = Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_lowpeak_poisson_{TARGET_RPM}_stitched.csv"

if poisson_csv.exists():
    print(f"Step 4: 检测到已有泊松文件，跳过 {poisson_csv.name}")
else:
    print(f"Step 4: 泊松插值（目标 {TARGET_RPM} RPM）")
    print("-" * 40)

    from scripts.data_processor.modules.interpolator import DataInterpolator
    from scripts.data_processor.config.settings import GlobalConfig

    df_for_interp = pd.read_csv(stitched_csv)
    df_for_interp["income_time"] = pd.to_datetime(df_for_interp["income_time"])

    orig_peak = df_for_interp["income_time"].dt.floor("1min").value_counts().max()
    print(f"  原始峰值: {orig_peak} RPM，目标: {TARGET_RPM} RPM")

    cfg_interp = GlobalConfig(
        output_dir=OUTPUT_DIR,
        model_name=MODEL_NAME,
        interpolate_peak_target=TARGET_RPM,
    )
    interp = DataInterpolator(cfg_interp)

    plot_file = Path(OUTPUT_DIR) / f"{MODEL_NAME}_lowpeak_poisson_{TARGET_RPM}_compare.html"
    ok = interp.interpolate_by_peak(
        input_file=str(stitched_csv),
        source_file=str(stitched_csv),
        output_file=str(poisson_csv),
        peak_target=TARGET_RPM,
        time_column="income_time",
        plot_html=str(plot_file),
    )

    if not ok:
        print("❌ 插值失败")
        sys.exit(1)

    if poisson_csv.exists():
        df_result = pd.read_csv(poisson_csv)
        result_peak = df_result["income_time"].pipe(lambda s: pd.to_datetime(s)).dt.floor("1min").value_counts().max()
        print(f"  ✅ 插值完成: {len(df_result):,} 条，峰值 {result_peak} RPM")
        print(f"  → {poisson_csv.name}\n")
    else:
        print(f"  ⚠️  找不到插值输出文件，检查 DataInterpolator 输出格式")

# ============================================================
# Step 5：脏数据过滤（messages content 为 list 的行）
# ============================================================
if poisson_csv.exists():
    print("Step 5: 脏数据过滤")
    print("-" * 40)

    df_clean = pd.read_csv(poisson_csv, dtype={"messages": str})
    before = len(df_clean)

    def is_valid_messages(m):
        if not isinstance(m, str) or not m.strip():
            return False
        try:
            parsed = json.loads(m)
            if isinstance(parsed, list):
                for item in parsed:
                    if isinstance(item, dict) and isinstance(item.get("content"), list):
                        return False
            return True
        except Exception:
            return False

    mask = df_clean["messages"].apply(is_valid_messages)
    df_clean = df_clean[mask].reset_index(drop=True)
    after = len(df_clean)
    removed = before - after
    print(f"  过滤前: {before:,} 条，过滤后: {after:,} 条（移除 {removed} 条多模态行）")
    df_clean.to_csv(poisson_csv, index=False)
    print(f"  ✅ 已覆盖写回 {poisson_csv.name}\n")

# ============================================================
# Step 6：README
# ============================================================
print("Step 6: 写 README.md")

peak_after = "（未计算）"
rows_after = 0
if poisson_csv.exists():
    try:
        df_readme = pd.read_csv(poisson_csv)
        rows_after = len(df_readme)
        df_readme["income_time"] = pd.to_datetime(df_readme["income_time"])
        peak_after = f"{df_readme['income_time'].dt.floor('1min').value_counts().max()} RPM"
    except Exception:
        pass

readme_path = Path(OUTPUT_DIR) / "README.md"
readme_content = f"""# xinghan-tarot-72b-agentv1 数据集

## 概述

| 项目 | 内容 |
|------|------|
| 模型 | xinghan-tarot-72b-agentv1 |
| 源数据目录 | {BY_DAY_DIR} |
| 输出目录 | {OUTPUT_DIR} |
| 目标 RPM | {TARGET_RPM} RPM（单实例 demo 测试） |

## 数据文件

| 文件 | 说明 |
|------|------|
| `{MODEL_NAME}_selected_combined_3days_peak.csv` | 3 天峰值窗口采样（凌晨 00:00~00:30）|
| `{MODEL_NAME}_selected_combined_3days_peak_stitched.csv` | 时间戳拼接（消除段间大间隔）|
| `{MODEL_NAME}_selected_combined_3days_peak_poisson_{TARGET_RPM}_stitched.csv` | 泊松插值至 {TARGET_RPM} RPM（{rows_after:,} 条，峰值 {peak_after}）|

## 峰值窗口

| 窗口 | 描述 |
|------|------|
| 2025-08-04 00:00~00:30 | 凌晨峰值 ~946 RPM |
| 2025-08-12 00:00~00:30 | 凌晨峰值 ~953 RPM |
| 2025-08-16 00:00~00:30 | 凌晨峰值 ~971 RPM |

## 数据格式

- **情况 A**（JSONL 线上日志），DataConverter 已处理完毕（in `by_day/`）
- `income_time`：请求时间戳（Asia/Shanghai，去时区）
- `messages`：完整 messages JSON（含 system+user prompt）
- `old_response`：模型历史回复（用于 token 长度估算）
- avg_output_len ≈ **200 tokens**（非推理型，无 <think> 标签）
"""

readme_path.write_text(readme_content, encoding="utf-8")
print(f"  ✅ {readme_path}\n")

print("=" * 60)
print("✅ 数据处理完成")
print(f"  回放数据集: {poisson_csv}")
print("=" * 60)
