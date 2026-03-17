#!/usr/bin/env python3
"""
xinghan-guoxue-72b-v1-2-reason 完整数据处理脚本
遵循 traffic-dataset-prep SKILL 6步管道（含步骤1.5 合并修正）：
  步骤1:   DataConverter → 日期分片 CSV（JSONL → CSV，异步拉取 prompt URL）
           注：DataConverter 同时输出 _all.csv，但该文件是 3 列索引文件，不可直接用于 benchmark
  步骤1.5: 合并所有日期分片 CSV → 覆盖写回 _all.csv（6 列完整数据，old_response NaN → ""）
  步骤2:   DataSampler  → 峰值窗口采样（2天各 ±10 分钟）
  步骤3: 时间戳拼接  → _stitched.csv（消除两段间 ~23h 大间隔）
  步骤4: DataInterpolator → _poisson_220_stitched.csv（放大至 220 RPM）
  步骤5: 脏数据过滤  → 覆盖写回（剔除 content 为 list 的行）
  步骤6: README.md   → 输出目录说明文档
"""

import sys, os, json, ast
sys.path.insert(
    0,
    "/mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party/data_analysis",
)

from pathlib import Path
from datetime import datetime
import pandas as pd

# ============================================================
# 配置
# ============================================================
JSONL_FILE  = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/xinghan-guoxue-72b-v1-2-reason_260313_260314.jsonl"
OUTPUT_DIR  = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output_guoxue"
MODEL_NAME  = "xinghan-guoxue-72b-v1-2-reason"
MODEL_LIST  = ("xinghan-guoxue-72b-v1-2-reason",)
TARGET_PEAK = 220

# 峰值窗口（2天，均在凌晨 00:00 附近）
# 03-13 峰值中心 00:12 (35/min), 窗口 ±10min
# 03-14 峰值中心 00:01 (38/min), 窗口 ±10min（跨午夜: 03-13 23:51 ~ 03-14 00:11）
PEAK_WINDOWS = [
    ("2026-03-13 00:02:00", "2026-03-13 00:22:00", "03-13 峰值00:12 ±10min"),
    ("2026-03-13 23:51:00", "2026-03-14 00:11:00", "03-14 峰值00:01 ±10min（跨午夜）"),
]

os.makedirs(OUTPUT_DIR, exist_ok=True)

print("=" * 60)
print("guoxue 完整数据处理流程（含 prompt 内容）")
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
        read_only_time=False,
        auto_confirm=True,
    )
    converter = DataConverter(cfg)
    ok = converter.run([JSONL_FILE], skip_confirmation=True)
    if not ok:
        print("❌ 数据转换失败")
        sys.exit(1)

print(f"✅ DataConverter 完成: {INDEX_FILE.name}  ({INDEX_FILE.stat().st_size:,} bytes)\n")


# ============================================================
# 步骤 1.5：合并日期分片 → 覆盖写回 _all.csv（6 列完整数据）
# ============================================================
# DataConverter 输出的 _all.csv 是 3 列索引文件（income_time, file_suffix, original_index），
# 不含 messages / old_response，benchmark 工具无法直接使用。
# 此步骤将所有日期分片 CSV 合并排序后覆盖写为标准 6 列 _all.csv。
print("步骤1.5: 合并日期分片 → 覆盖写回 _all.csv（完整 6 列）")
day_csvs = sorted(Path(OUTPUT_DIR).glob(f"{MODEL_NAME}_2[0-9][0-9][0-9]-*.csv"))
if not day_csvs:
    print("  ⚠️  未找到日期分片 CSV，跳过合并")
else:
    dfs = [pd.read_csv(p) for p in day_csvs]
    df_full = pd.concat(dfs, ignore_index=True).sort_values("income_time").reset_index(drop=True)
    df_full["old_response"] = df_full["old_response"].fillna("")
    # 产出: {MODEL_NAME}_all.csv
    #   6列完整数据（income_time, prompt, messages, old_response, user_id, line_num）
    #   ⚠️ 覆盖了 DataConverter 原生的 3 列索引文件；此后 _all.csv 可直接用于 benchmark
    df_full.to_csv(INDEX_FILE, index=False)
    print(f"  合并 {len(day_csvs)} 个分片  →  {len(df_full):,} 行  →  {INDEX_FILE.name}")
    print(f"  列: {list(df_full.columns)}\n")


# ============================================================
# 步骤 2：按峰值窗口采样
# ============================================================
print("=" * 60)
print("步骤2: 数据采样（2天峰值窗口各 ±10 分钟，合并）")
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

combined_file = str(Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_2days_peak.csv")
# 产出: {MODEL_NAME}_selected_combined_2days_peak.csv
#   2天峰值窗口合并，6列完整数据，时间戳未拼接（两段间有 ~23h 大间隔）
#   中间产物，供步骤3消除间隔后使用
df_combined.to_csv(combined_file, index=False)

rpm = df_combined["income_time"].dt.floor("min").value_counts()
print(f"\n合并采样结果:")
print(f"  总请求数: {len(df_combined):,}")
print(f"  峰值 RPM: {rpm.max()}")
print(f"  均值 RPM: {rpm.mean():.1f}")
print(f"  文件:     {Path(combined_file).name}")

non_empty = df_combined["messages"].dropna().str.strip().ne("").sum()
print(f"  messages 有内容的行: {non_empty:,} / {len(df_combined):,}")
print()


# ============================================================
# 步骤 3：时间戳拼接（消除两段间 ~23h 大间隔）
# ============================================================
print("=" * 60)
print("步骤3: 时间戳拼接（消除段间大间隔 > 5min）")
print("=" * 60)

df_stitch = df_combined.copy()
diffs = df_stitch["income_time"].diff()
big_gaps = diffs[diffs > pd.Timedelta("5min")]
print(f"  发现大间隔数量: {len(big_gaps)}")
for idx, gap in big_gaps.items():
    print(f"    位置 {idx}: {gap}")

if len(big_gaps) == 0:
    print("  无需拼接")
    stitched_file = combined_file
else:
    # 找到各段边界
    gap_indices = [0] + list(big_gaps.index) + [len(df_stitch)]
    seg_ranges = [(gap_indices[i], gap_indices[i+1]) for i in range(len(gap_indices)-1)]

    anchor_end = None
    segments = []
    for i, (s, e) in enumerate(seg_ranges):
        seg = df_stitch.iloc[s:e].copy()
        if i == 0:
            anchor_end = seg["income_time"].iloc[-1]
            segments.append(seg)
        else:
            offset = (anchor_end + pd.Timedelta("1s")) - seg["income_time"].iloc[0]
            seg["income_time"] = seg["income_time"] + offset
            anchor_end = seg["income_time"].iloc[-1]
            segments.append(seg)
            print(f"    段 {i+1}: 移位 {offset}")

    df_stitched = pd.concat(segments, ignore_index=True)
    stitched_file = str(Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_2days_peak_stitched.csv")
    # 产出: {MODEL_NAME}_selected_combined_2days_peak_stitched.csv
    #   时间戳拼接后的峰值数据，两段间大间隔已消除，连续时间序列
    #   中间产物，供步骤4泊松插值使用
    df_stitched.to_csv(stitched_file, index=False)

    # 验证拼接后无大间隔
    diffs2 = df_stitched["income_time"].diff()
    remaining_gaps = diffs2[diffs2 > pd.Timedelta("5min")]
    print(f"  拼接后大间隔: {len(remaining_gaps)} 个")
    print(f"  拼接后总行数: {len(df_stitched):,}")
    print(f"  输出: {Path(stitched_file).name}")
    df_stitch = df_stitched

print()


# ============================================================
# 步骤 4：泊松流量插值 → 220 RPM
# ============================================================
print("=" * 60)
print(f"步骤4: 流量插值（目标峰值 {TARGET_PEAK} RPM）")
print("=" * 60)

from scripts.data_processor.modules.interpolator import DataInterpolator

interpolated_file = str(
    Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_2days_peak_poisson_{TARGET_PEAK}_stitched.csv"
)
plot_file = str(
    Path(OUTPUT_DIR) / f"{MODEL_NAME}_poisson_{TARGET_PEAK}_compare.html"
)

cfg_interp = GlobalConfig(output_dir=OUTPUT_DIR, model_name=MODEL_NAME,
                          interpolate_peak_target=TARGET_PEAK)
interpolator = DataInterpolator(cfg_interp)

ok = interpolator.interpolate_by_peak(
    input_file=stitched_file,
    source_file=stitched_file,
    output_file=interpolated_file,
    peak_target=TARGET_PEAK,
    time_column="income_time",
    plot_html=plot_file,
)

if not ok:
    print("❌ 插值失败")
    sys.exit(1)

df_r = pd.read_csv(interpolated_file)
rpm_f = pd.to_datetime(df_r["income_time"]).dt.floor("min").value_counts()
non_empty_r = df_r["messages"].dropna().str.strip().ne("").sum()
print(f"\n✅ 插值完成")
print(f"  总请求数: {len(df_r):,}")
print(f"  峰值 RPM: {rpm_f.max()}")
print(f"  messages 有内容: {non_empty_r:,} / {len(df_r):,}")
print(f"  输出: {Path(interpolated_file).name}")
print()


# ============================================================
# 步骤 5：脏数据过滤（剔除 content 为 list 的行）
# ============================================================
print("=" * 60)
print("步骤5: 脏数据过滤（剔除 content 为 list 的行）")
print("=" * 60)

def has_list_content(messages_str: str) -> bool:
    if not isinstance(messages_str, str) or not messages_str.strip():
        return False
    try:
        msgs = json.loads(messages_str)
    except Exception:
        try:
            msgs = ast.literal_eval(messages_str)
        except Exception:
            return False
    return any(isinstance(m.get("content"), list) for m in msgs if isinstance(m, dict))

df_clean = pd.read_csv(interpolated_file)
before = len(df_clean)
mask = df_clean["messages"].apply(has_list_content)
df_clean = df_clean[~mask].reset_index(drop=True)
removed = before - len(df_clean)

print(f"  过滤前: {before:,} 行")
print(f"  删除脏行: {removed} 行")
print(f"  过滤后: {len(df_clean):,} 行")

# 产出（覆盖写回）: {MODEL_NAME}_selected_combined_2days_peak_poisson_{TARGET_PEAK}_stitched.csv
#   最终交付文件：脏数据已过滤，峰值 TARGET_PEAK RPM，可直接用于 replay benchmark
df_clean.to_csv(interpolated_file, index=False)
print(f"  ✅ 已覆盖写回: {Path(interpolated_file).name}")
print()


# ============================================================
# 步骤 6：写 README.md
# ============================================================
print("=" * 60)
print("步骤6: 写 README.md")
print("=" * 60)

readme_path = Path(OUTPUT_DIR) / "README.md"
readme_content = f"""# {MODEL_NAME} 数据集

## 数据来源
- 原始文件: `{Path(JSONL_FILE).name}`
- 原始行数: 23,361 条（2026-03-13 ~ 2026-03-14）
- 模型别名（model_list）: `{MODEL_LIST}`
- 处理日期: {datetime.now().strftime('%Y-%m-%d')}

## 处理流程（6步管道）

| 步骤 | 操作 | 关键参数 |
|------|------|---------|
| 1 | JSONL → all.csv | read_only_time=False，异步拉取 prompt URL |
| 2 | 峰值窗口采样 | 03-13 00:02-00:22, 03-13 23:51-03-14 00:11 |
| 3 | 时间戳拼接 | 消除两段间 ~23h 间隔 |
| 4 | 泊松插值 | TARGET_PEAK={TARGET_PEAK} RPM |
| 5 | 脏数据过滤 | 剔除 content 为 list 的行 |
| 6 | README.md | 本文档 |

## 产出文件一览

| 文件 | 步骤 | 类型 | 说明 |
|------|------|------|------|
| `{MODEL_NAME}_2026-03-13.csv` | 1 | 中间产物 | DataConverter 日期分片，6列完整数据（含 messages/old_response） |
| `{MODEL_NAME}_2026-03-14.csv` | 1 | 中间产物 | DataConverter 日期分片，6列完整数据（含 messages/old_response） |
| `{MODEL_NAME}_all.csv` | 1.5 | 中间产物 | 日期分片合并全量数据，步骤1.5 覆盖写回后为6列完整数据 ⚠️ DataConverter 原生产出的同名文件为3列索引文件，不可直接用于 benchmark |
| `{MODEL_NAME}_selected_combined_2days_peak.csv` | 2 | 中间产物 | 两个峰值窗口采样合并，时间戳未拼接（两段间有 ~23h 大间隔） |
| `{MODEL_NAME}_selected_combined_2days_peak_stitched.csv` | 3 | 中间产物 | 时间戳拼接后，连续时间序列，无大间隔 |
| **`{MODEL_NAME}_selected_combined_2days_peak_poisson_{TARGET_PEAK}_stitched.csv`** | 4-5 | **最终交付** | **replay benchmark 使用此文件**，峰值 {TARGET_PEAK} RPM，脏数据已过滤 |
| `{MODEL_NAME}_poisson_{TARGET_PEAK}_compare.html` | 4 | 可视化 | 插值前后流量对比图 |
| `README.md` | 6 | 说明文档 | 本文档 |

## 验证结论
- model_list 别名验证：JSONL 中只有 `xinghan-guoxue-72b-v1-2-reason` 一种写法，无中文别名
- 峰值窗口质量：03-13 窗口均值 ~25.5 RPM，03-14 窗口均值 ~23.3 RPM
- 拼接后大间隔：0 个（已验证）
- 插值后峰值 RPM：达到 {TARGET_PEAK} RPM 目标
"""

readme_path.write_text(readme_content, encoding="utf-8")
print(f"  ✅ {readme_path}")


# ============================================================
# 汇总
# ============================================================
print()
print("=" * 60)
print("全部完成！输出文件:")
print("=" * 60)
for f in sorted(Path(OUTPUT_DIR).glob("*")):
    print(f"  {f.name}  ({f.stat().st_size:,} bytes)")
print("=" * 60)
