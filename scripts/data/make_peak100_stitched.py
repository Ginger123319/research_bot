#!/usr/bin/env python3
"""
对 xinghan-ziwei-32b-v1-1_selected_combined_3days_peak.csv 做：
  步骤1: 时间戳拼接 —— 三段首尾相连（消除 ~23.5 小时间隔）
  步骤2: 泊松插值 —— 峰值放大到 100 RPM
  输出: xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_poisson_100_stitched.csv
"""

import sys
sys.path.insert(0, "/mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party/data_analysis")

import pandas as pd
from pathlib import Path

OUTPUT_DIR  = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output"
MODEL_NAME  = "xinghan-ziwei-32b-v1-1"
TARGET_PEAK = 100
SEG_GAP     = pd.Timedelta("1s")

INPUT_FILE  = Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_peak.csv"
STITCHED_FILE = Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_peak_stitched.csv"
OUTPUT_FILE   = Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_peak_poisson_{TARGET_PEAK}_stitched.csv"
SOURCE_FILE  = Path(OUTPUT_DIR) / f"{MODEL_NAME}_2026-03-04.csv"  # 插值用的源数据池（含完整 prompt/messages）
PLOT_FILE    = Path(OUTPUT_DIR) / f"{MODEL_NAME}_poisson_{TARGET_PEAK}_compare.html"

print("=" * 60)
print(f"步骤1: 时间戳拼接")
print("=" * 60)

df = pd.read_csv(INPUT_FILE, parse_dates=["income_time"])
df = df.sort_values("income_time").reset_index(drop=True)

print(f"  原始数据: {len(df)} 条")

# 找段边界
diffs = df["income_time"].diff()
big_gap_indices = diffs[diffs > pd.Timedelta("5min")].index.tolist()

seg_ranges = []
prev = 0
for idx in big_gap_indices:
    seg_ranges.append((prev, idx))
    prev = idx
seg_ranges.append((prev, len(df)))

print(f"  检测到 {len(seg_ranges)} 段:")
for i, (s, e) in enumerate(seg_ranges):
    seg = df.iloc[s:e]
    print(f"    段{i+1}: 行{s}~{e-1} ({e-s}条) "
          f"{seg['income_time'].iloc[0]} ~ {seg['income_time'].iloc[-1]}")

# 平移拼接
segments = []
anchor_end = None
for i, (s, e) in enumerate(seg_ranges):
    seg = df.iloc[s:e].copy()
    if i == 0:
        segments.append(seg)
        anchor_end = seg["income_time"].iloc[-1]
    else:
        seg_start = seg["income_time"].iloc[0]
        offset = (anchor_end + SEG_GAP) - seg_start
        seg["income_time"] = seg["income_time"] + offset
        segments.append(seg)
        anchor_end = seg["income_time"].iloc[-1]
        print(f"    段{i+1} 平移: {offset}  → {seg['income_time'].iloc[0]} ~ {anchor_end}")

df_stitched = pd.concat(segments, ignore_index=True)
df_stitched["income_time"] = df_stitched["income_time"].dt.strftime("%Y-%m-%d %H:%M:%S")
df_stitched.to_csv(STITCHED_FILE, index=False)
print(f"\n  已保存: {STITCHED_FILE.name}")

# 验证
df_v = pd.read_csv(STITCHED_FILE, parse_dates=["income_time"])
rpm_v = df_v["income_time"].dt.floor("min").value_counts()
remaining = df_v["income_time"].diff()[df_v["income_time"].diff() > pd.Timedelta("5min")]
print(f"\n  拼接结果: {len(df_v)} 条  |  时长: {(df_v['income_time'].max()-df_v['income_time'].min()).total_seconds()/60:.1f} 分钟")
print(f"  峰值 RPM: {rpm_v.max()}  |  剩余大间隔: {len(remaining)} 个（应为0）")


print()
print("=" * 60)
print(f"步骤2: 泊松插值 → 峰值 {TARGET_PEAK} RPM")
print("=" * 60)

from scripts.data_processor.config.settings import GlobalConfig
from scripts.data_processor.modules.interpolator import DataInterpolator

cfg = GlobalConfig(
    output_dir=OUTPUT_DIR,
    model_name=MODEL_NAME,
    interpolate_peak_target=TARGET_PEAK,
)
interpolator = DataInterpolator(cfg)

ok = interpolator.interpolate_by_peak(
    input_file=str(STITCHED_FILE),
    source_file=str(SOURCE_FILE),
    output_file=str(OUTPUT_FILE),
    peak_target=TARGET_PEAK,
    time_column="income_time",
    plot_html=str(PLOT_FILE),
)



if ok:
    df_r = pd.read_csv(OUTPUT_FILE, parse_dates=["income_time"])
    rpm_r = df_r["income_time"].dt.floor("min").value_counts()
    remaining_r = df_r["income_time"].diff()[df_r["income_time"].diff() > pd.Timedelta("5min")]
    print(f"\n✅ 插值完成")
    print(f"  总请求数: {len(df_r)}")
    print(f"  时间跨度: {df_r['income_time'].min()} ~ {df_r['income_time'].max()}")
    print(f"  峰值 RPM: {rpm_r.max()}")
    print(f"  均值 RPM: {rpm_r.mean():.1f}")
    print(f"  大间隔:   {len(remaining_r)} 个（应为0）")
    print(f"  输出文件: {OUTPUT_FILE.name}")
    print(f"  对比图表: {PLOT_FILE.name}")
else:
    print("❌ 插值失败")
    sys.exit(1)

print()
print("=" * 60)
print("全部完成！")
print("=" * 60)
