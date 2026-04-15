#!/usr/bin/env python3
"""
xinghan-hepan-72b-v1-2（合盘塔罗）完整数据处理脚本
遵循 traffic-dataset-prep SKILL 5步管道：
  步骤1: DataConverter (read_only_time=False) → _all.csv (按天分片 + 全量合并)
  步骤2: DataSampler → 三天峰值窗口各 ±10 分钟采样合并
  步骤3: 时间戳拼接 → 消除段间 >5min 大间隔
  步骤4: DataInterpolator (泊松插值) → 峰值放大至 TARGET_RPM
  步骤5: 脏数据过滤 → 剔除 messages.content 为 list 的多模态行

income_time 来源：DataConverter 内部使用 messages[0].get("time")，
                  fallback 到 request_info.get("session_time")。
数据: hepan_all_0302_0304.jsonl，时间范围 2026-03-02 ~ 2026-03-04，
      三天峰值均在午夜 00:00~00:25。
      注意：model_list 必须同时包含 "xinghan-hepan-72b-v1-2" 和 "星盘合盘"，
            仅用英文名只能捞到 ~18,567 条（31%），加上中文别名后总量 ~58,871 条。
      实测峰值约 63 RPM（全量），目标插值至 TARGET_PEAK。
"""

import sys
import os
import json
import ast

from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "third_party/data_analysis"))
from datetime import datetime
import pandas as pd

# ============================================================
# 配置
# ============================================================
JSONL_FILE  = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/hepan_all_0302_0304.jsonl"
OUTPUT_DIR  = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output_henpan_tarot"
MODEL_NAME  = "xinghan-hepan-72b-v1-2"
MODEL_LIST  = ("xinghan-hepan-72b-v1-2", "星盘合盘")
TARGET_PEAK = 150  # 目标峰值 RPM（全量实测最高 74 RPM，放大 ~2x）
SEG_GAP     = pd.Timedelta("1s")

# 三天峰值窗口（基于全量 58,871 条数据 messages[0].time 分析）
# 03-02 峰值 00:02 → 74 RPM，窗口 00:00 ~ 00:22
# 03-03 峰值 00:01 → 63 RPM，窗口 00:00 ~ 00:21
# 03-04 峰值 00:03 → 55 RPM，窗口 00:00 ~ 00:23
PEAK_WINDOWS = [
    ("2026-03-02 00:00:00", "2026-03-02 00:22:00", "03-02 峰值00:02 ±11min (74 RPM)"),
    ("2026-03-03 00:00:00", "2026-03-03 00:21:00", "03-03 峰值00:01 ±10min (63 RPM)"),
    ("2026-03-04 00:00:00", "2026-03-04 00:23:00", "03-04 峰值00:03 ±10min (55 RPM)"),
]

os.makedirs(OUTPUT_DIR, exist_ok=True)

print("=" * 60)
print("合盘塔罗 完整数据处理流程（5步管道）")
print("=" * 60)
print(f"  模型:     {MODEL_NAME}")
print(f"  输出目录: {OUTPUT_DIR}")
print(f"  目标峰值: {TARGET_PEAK} RPM（全量实测峰值 74 RPM，放大 ~2x）")
print(f"  峰值窗口: {len(PEAK_WINDOWS)} 段（时间戳来源: messages[0].time）")
print()


# ============================================================
# 步骤1：完整数据转换（read_only_time=False）
# ============================================================
INDEX_FILE = Path(OUTPUT_DIR) / f"{MODEL_NAME}_all.csv"

if INDEX_FILE.exists():
    print(f"步骤1: 检测到已有完整索引 {INDEX_FILE.name}，跳过转换")
    df_idx = pd.read_csv(INDEX_FILE)
    print(f"  已有记录数: {len(df_idx):,}\n")
else:
    print("=" * 60)
    print("步骤1: 完整数据转换（异步拉取 prompt URL，约需 5-15 分钟）")
    print("=" * 60)

    from scripts.data_processor.config.settings import GlobalConfig
    from scripts.data_processor.modules.converter import DataConverter

    cfg = GlobalConfig(
        input_files=[JSONL_FILE],
        output_dir=OUTPUT_DIR,
        model_name=MODEL_NAME,
        model_list=MODEL_LIST,
        read_only_time=False,
        auto_confirm=True,
    )
    converter = DataConverter(cfg)
    ok = converter.run([JSONL_FILE], skip_confirmation=True)
    if not ok:
        print("❌ 数据转换失败")
        sys.exit(1)

INDEX_FILE_SIZE = INDEX_FILE.stat().st_size if INDEX_FILE.exists() else 0
print(f"✅ 完整索引: {INDEX_FILE.name}  ({INDEX_FILE_SIZE:,} bytes)\n")

# 验证 _all.csv
df_all = pd.read_csv(INDEX_FILE)
non_empty_all = df_all["messages"].dropna().str.strip().ne("").sum() if "messages" in df_all.columns else 0
print(f"  [验证] 全量 messages 有内容: {non_empty_all:,} / {len(df_all):,}\n")


# ============================================================
# 步骤2：按峰值窗口采样
# ============================================================
print("=" * 60)
print("步骤2: 峰值窗口采样（三天峰值各 ±10 分钟，合并）")
print("=" * 60)

from scripts.data_processor.config.settings import GlobalConfig
from scripts.data_processor.modules.sampler import DataSampler

cfg_sample = GlobalConfig(
    output_dir=OUTPUT_DIR,
    model_name=MODEL_NAME,
    model_list=MODEL_LIST,
    read_only_time=False,
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

combined_file = Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_peak.csv"
df_combined.to_csv(combined_file, index=False)

rpm_combined = df_combined["income_time"].dt.floor("min").value_counts()
non_empty_comb = df_combined["messages"].dropna().str.strip().ne("").sum()
print(f"\n合并采样结果:")
print(f"  总请求数: {len(df_combined):,}")
print(f"  峰值 RPM: {rpm_combined.max()}")
print(f"  均值 RPM: {rpm_combined.mean():.1f}")
print(f"  messages 有内容: {non_empty_comb:,} / {len(df_combined):,}")
print(f"  文件: {combined_file.name}\n")


# ============================================================
# 步骤3：时间戳拼接（消除段间大间隔）
# ============================================================
print("=" * 60)
print("步骤3: 时间戳拼接（消除 >5min 大间隔）")
print("=" * 60)

df = pd.read_csv(combined_file, parse_dates=["income_time"])
df = df.sort_values("income_time").reset_index(drop=True)
print(f"  输入数据: {len(df)} 条")

# 检测段边界
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
    print(f"    段{i+1}: {e-s}条  {seg['income_time'].iloc[0]} ~ {seg['income_time'].iloc[-1]}")

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

stitched_file = Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_peak_stitched.csv"
df_stitched.to_csv(stitched_file, index=False)

# 验证
df_v = pd.read_csv(stitched_file, parse_dates=["income_time"])
rpm_v = df_v["income_time"].dt.floor("min").value_counts()
remaining = df_v["income_time"].diff()[df_v["income_time"].diff() > pd.Timedelta("5min")]
duration = (df_v["income_time"].max() - df_v["income_time"].min()).total_seconds() / 60
print(f"\n  拼接结果: {len(df_v)} 条  |  时长: {duration:.1f} 分钟")
print(f"  峰值 RPM: {rpm_v.max()}  |  剩余大间隔: {len(remaining)} 个（应为0）✅")
print(f"  文件: {stitched_file.name}\n")


# ============================================================
# 步骤4：泊松流量插值 → TARGET_PEAK RPM
# ============================================================
print("=" * 60)
print(f"步骤4: 泊松流量插值（目标峰值 {TARGET_PEAK} RPM）")
print("=" * 60)

from scripts.data_processor.modules.interpolator import DataInterpolator

output_file = Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_3days_peak_poisson_{TARGET_PEAK}_stitched.csv"
plot_file   = Path(OUTPUT_DIR) / f"{MODEL_NAME}_poisson_{TARGET_PEAK}_compare.html"

cfg_interp = GlobalConfig(
    output_dir=OUTPUT_DIR,
    model_name=MODEL_NAME,
    interpolate_peak_target=TARGET_PEAK,
)
interpolator = DataInterpolator(cfg_interp)

ok = interpolator.interpolate_by_peak(
    input_file=str(stitched_file),
    source_file=str(stitched_file),  # 拼接后 CSV 同时作为数据源池
    output_file=str(output_file),
    peak_target=TARGET_PEAK,
    time_column="income_time",
    plot_html=str(plot_file),
)

if not ok:
    print("❌ 插值失败")
    sys.exit(1)

df_interp = pd.read_csv(output_file, parse_dates=["income_time"])
rpm_interp = df_interp["income_time"].dt.floor("min").value_counts()
non_empty_interp = df_interp["messages"].dropna().str.strip().ne("").sum()
print(f"\n✅ 插值完成")
print(f"  总请求数: {len(df_interp):,}")
print(f"  峰值 RPM: {rpm_interp.max()}")
print(f"  均值 RPM: {rpm_interp.mean():.1f}")
print(f"  messages 有内容: {non_empty_interp:,} / {len(df_interp):,}")
print(f"  文件: {output_file.name}\n")


# ============================================================
# 步骤5：脏数据过滤（剔除 content 为 list 的多模态行）
# ============================================================
print("=" * 60)
print("步骤5: 脏数据过滤（messages.content 为 list 的行）")
print("=" * 60)

def has_list_content(messages_str: str) -> bool:
    if pd.isna(messages_str) or str(messages_str).strip() == "":
        return False
    try:
        msgs = json.loads(messages_str)
    except Exception:
        try:
            msgs = ast.literal_eval(str(messages_str))
        except Exception:
            return False
    return any(isinstance(m.get("content"), list) for m in msgs if isinstance(m, dict))

for target_csv, label in [(output_file, "poisson_stitched"), (INDEX_FILE, "_all")]:
    if not target_csv.exists():
        continue
    df_t = pd.read_csv(target_csv)
    before = len(df_t)
    if "messages" in df_t.columns:
        dirty_mask = df_t["messages"].apply(has_list_content)
        dirty_count = dirty_mask.sum()
        if dirty_count > 0:
            df_t = df_t[~dirty_mask].reset_index(drop=True)
            df_t.to_csv(target_csv, index=False)
            print(f"  [{label}] 移除脏行: {dirty_count} 条  ({before} → {len(df_t)})")
        else:
            print(f"  [{label}] 无脏数据 ✅  ({before} 条)")
    else:
        print(f"  [{label}] 无 messages 列，跳过")

print()


# ============================================================
# 汇总
# ============================================================
print("=" * 60)
print("全部完成！输出文件汇总:")
print("=" * 60)
total_size = 0
for f in sorted(Path(OUTPUT_DIR).iterdir()):
    if f.suffix in (".csv", ".html"):
        size = f.stat().st_size
        total_size += size
        rows = ""
        if f.suffix == ".csv":
            try:
                r = sum(1 for _ in open(f)) - 1
                rows = f"  {r:,} 行"
            except:
                pass
        print(f"  {f.name:<70}  {size:>12,} bytes{rows}")
print(f"\n  合计: {total_size:,} bytes")
print("=" * 60)
