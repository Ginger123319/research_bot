#!/usr/bin/env python3
"""
xinghan-ziwei-32b-v1-1 完整数据处理脚本
read_only_time=False：异步拉取 prompt URL，messages/prompt 字段有真实内容
步骤：
  1. 完整数据转换（异步并发拉取 COS URL）
  2. 三天峰值窗口各 ±10 分钟采样合并
  3. 泊松插值至目标峰值 29 RPM
"""

import sys, os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "third_party/data_analysis"))
from datetime import datetime
import pandas as pd

# ============================================================
# 配置
# ============================================================
JSONL_FILE  = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/xinghan-ziwei-32b-v1-1_260303_260305.jsonl"
OUTPUT_DIR  = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output"
MODEL_NAME  = "xinghan-ziwei-32b-v1-1"
MODEL_LIST  = ("xinghan-ziwei-32b-v1-1", "紫微")
TARGET_PEAK = 29

PEAK_WINDOWS = [
    ("2026-03-03 00:09:00", "2026-03-03 00:29:00", "03-03 峰值00:19 ±10min"),
    ("2026-03-03 23:58:00", "2026-03-04 00:18:00", "03-04 峰值00:08 ±10min"),
    ("2026-03-05 00:00:00", "2026-03-05 00:20:00", "03-05 峰值00:10 ±10min"),
]

os.makedirs(OUTPUT_DIR, exist_ok=True)

print("=" * 60)
print("紫微完整数据处理流程（含 prompt 内容）")
print("=" * 60)
print(f"  模型:     {MODEL_NAME}")
print(f"  输出目录: {OUTPUT_DIR}")
print(f"  目标峰值: {TARGET_PEAK} RPM")
print()


# ============================================================
# 步骤 1：完整数据转换（read_only_time=False）
# ============================================================
INDEX_FILE = Path(OUTPUT_DIR) / f"{MODEL_NAME}_all.csv"

if INDEX_FILE.exists():
    print(f"步骤1: 检测到已有完整索引 {INDEX_FILE.name}，跳过转换")
    df_idx = pd.read_csv(INDEX_FILE)
    print(f"  已有记录数: {len(df_idx):,}\n")
else:
    print("=" * 60)
    print("步骤1: 完整数据转换（异步拉取 prompt URL，约需 2-5 分钟）")
    print("=" * 60)

    from scripts.data_processor.config.settings import GlobalConfig
    from scripts.data_processor.modules.converter import DataConverter

    cfg = GlobalConfig(
        input_files=[JSONL_FILE],
        output_dir=OUTPUT_DIR,
        model_name=MODEL_NAME,
        model_list=MODEL_LIST,
        read_only_time=False,   # 完整模式，拉取 prompt URL
        auto_confirm=True,
    )
    converter = DataConverter(cfg)
    ok = converter.run([JSONL_FILE], skip_confirmation=True)
    if not ok:
        print("❌ 数据转换失败")
        sys.exit(1)

print(f"✅ 完整索引: {INDEX_FILE.name}  ({INDEX_FILE.stat().st_size:,} bytes)\n")


# ============================================================
# 步骤 2：按峰值窗口采样（使用 DataSampler，标准模式）
# ============================================================
print("=" * 60)
print("步骤2: 数据采样 (三天峰值窗口各 ±10 分钟，合并)")
print("=" * 60)

from scripts.data_processor.config.settings import GlobalConfig
from scripts.data_processor.modules.sampler import DataSampler

cfg_sample = GlobalConfig(
    output_dir=OUTPUT_DIR,
    model_name=MODEL_NAME,
    model_list=MODEL_LIST,
    read_only_time=False,   # 与转换模式一致，sampler 找 {model}_all.csv
)
sampler = DataSampler(cfg_sample)

sampled_frames = []
for start_str, end_str, desc in PEAK_WINDOWS:
    start_dt = datetime.strptime(start_str, "%Y-%m-%d %H:%M:%S")
    end_dt   = datetime.strptime(end_str,   "%Y-%m-%d %H:%M:%S")
    print(f"\n  ▶ {desc}")
    print(f"    {start_str} ~ {end_str}")
    try:
        df_win = sampler._select_data(start_dt, end_dt)
        sampled_frames.append(df_win)
        print(f"    ✅ 采样 {len(df_win):,} 条")
    except (FileNotFoundError, ValueError) as e:
        print(f"    ⚠️  跳过: {e}")

if not sampled_frames:
    print("\n❌ 所有窗口均无数据")
    sys.exit(1)

df_combined = pd.concat(sampled_frames, ignore_index=True)
df_combined["income_time"] = pd.to_datetime(df_combined["income_time"])
df_combined = df_combined.sort_values("income_time").reset_index(drop=True)

combined_file = str(Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_peak.csv")
df_combined.to_csv(combined_file, index=False)

rpm = df_combined["income_time"].dt.floor("min").value_counts()
print(f"\n合并采样结果:")
print(f"  总请求数: {len(df_combined):,}")
print(f"  峰值 RPM: {rpm.max()}")
print(f"  均值 RPM: {rpm.mean():.1f}")
print(f"  文件:     {Path(combined_file).name}")

# 验证 messages 字段
non_empty = df_combined["messages"].dropna().str.strip().ne("").sum()
print(f"  messages 有内容的行: {non_empty:,} / {len(df_combined):,}")
print()


# ============================================================
# 步骤 3：泊松流量插值 → 29 RPM
# ============================================================
print("=" * 60)
print(f"步骤3: 流量插值 (目标峰值 {TARGET_PEAK} RPM)")
print("=" * 60)

from scripts.data_processor.modules.interpolator import DataInterpolator

# 源文件：用某天的完整 CSV（messages 有内容）
# 优先用 03-04（当天流量最高）
for candidate_suffix in ["2026-03-04", "2026-03-03", "2026-03-05"]:
    source_file = str(Path(OUTPUT_DIR) / f"{MODEL_NAME}_{candidate_suffix}.csv")
    if os.path.exists(source_file):
        print(f"  源文件: {MODEL_NAME}_{candidate_suffix}.csv")
        break
else:
    source_file = combined_file
    print(f"  源文件（回退）: {Path(combined_file).name}")

interpolated_file = str(
    Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_peak_poisson_{TARGET_PEAK}.csv"
)
plot_file = str(
    Path(OUTPUT_DIR) / f"{MODEL_NAME}_poisson_{TARGET_PEAK}_compare.html"
)

cfg_interp = GlobalConfig(output_dir=OUTPUT_DIR, model_name=MODEL_NAME,
                          interpolate_peak_target=TARGET_PEAK)
interpolator = DataInterpolator(cfg_interp)

ok = interpolator.interpolate_by_peak(
    input_file=combined_file,
    source_file=source_file,
    output_file=interpolated_file,
    peak_target=TARGET_PEAK,
    time_column="income_time",
    plot_html=plot_file,
)

if ok:
    df_r = pd.read_csv(interpolated_file)
    rpm_f = pd.to_datetime(df_r["income_time"]).dt.floor("min").value_counts()
    non_empty_r = df_r["messages"].dropna().str.strip().ne("").sum()
    print(f"\n✅ 插值完成")
    print(f"  总请求数: {len(df_r):,}")
    print(f"  峰值 RPM: {rpm_f.max()}")
    print(f"  messages 有内容: {non_empty_r:,} / {len(df_r):,}")
    print(f"  输出: {Path(interpolated_file).name}")
    print(f"  图表: {Path(plot_file).name}")
else:
    print("❌ 插值失败")
    sys.exit(1)


# ============================================================
# 汇总
# ============================================================
print()
print("=" * 60)
print("全部完成！输出文件:")
print("=" * 60)
for f in sorted(Path(OUTPUT_DIR).glob("*.csv")):
    print(f"  {f.name}  ({f.stat().st_size:,} bytes)")
for f in sorted(Path(OUTPUT_DIR).glob("*.html")):
    print(f"  {f.name}  ({f.stat().st_size:,} bytes)")
print("=" * 60)
