#!/usr/bin/env python3
"""
xinghan-guoxue-72b-v1-2-reason V2 数据处理脚本
数据源: guoxue-v1-2-online-2026-01-1631-downloaded-s50k.jsonl（真实线上数据，Jan 16-17 2026）
遵循 traffic-dataset-prep SKILL 6步管道（含步骤1.5 合并修正）：
  步骤1:   DataConverter → 日期分片 CSV（JSONL → CSV）
  步骤1.5: 合并所有日期分片 CSV → 覆盖写回 _all.csv（6 列完整数据，old_response 回填）
  步骤2:   DataSampler  → 峰值窗口采样（2个 20min 窗口）
  步骤3: 时间戳拼接  → _stitched.csv（消除两段间 ~22h 大间隔）
  步骤4: DataInterpolator → _poisson_256_stitched.csv（放大至 256 RPM）
  步骤5: 脏数据过滤  → 覆盖写回（剔除 content 为 list 的行）
  步骤6: README.md   → 输出目录说明文档

与 V1 的关键差异：
  - JSONL_FILE: 真实线上数据（非兜底）
  - MODEL_LIST: 增加别名 "八字深度"（线上日志中的模型标识）
  - TARGET_PEAK: 256 RPM（213+43，两段 Grafana 峰值叠加）
  - PEAK_WINDOWS: Jan 16 00:00~00:20（峰值 72 RPM）+ Jan 16 22:49~23:09（峰值 55 RPM）
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
JSONL_FILE  = "/home/ceceadmin/wnd/workspace/repo/SpecForge/wnd_dev/data/downloaded/guoxue-v1-2-online-2026-01-1631-downloaded-s50k.jsonl"
OUTPUT_DIR  = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output_guoxue_v2"
MODEL_NAME  = "xinghan-guoxue-72b-v1-2-reason"
MODEL_LIST  = ("xinghan-guoxue-72b-v1-2-reason", "八字深度")
TARGET_PEAK = 256

# 峰值窗口（2个 20min 窗口）
# 01-16 峰值中心 00:02 (72/min), 窗口 00:00~00:20
# 01-16 夜间峰值中心 22:59 (55/min), 窗口 22:49~23:09
PEAK_WINDOWS = [
    ("2026-01-16 00:00:00", "2026-01-16 00:20:00", "01-16 凌晨峰值00:02 ±10min"),
    ("2026-01-16 22:49:00", "2026-01-16 23:09:00", "01-16 夜间峰值22:59 ±10min"),
]

os.makedirs(OUTPUT_DIR, exist_ok=True)

print("=" * 60)
print("guoxue V2 数据处理流程（真实线上数据）")
print("=" * 60)
print(f"  模型:     {MODEL_NAME}")
print(f"  别名:     {MODEL_LIST}")
print(f"  输出目录: {OUTPUT_DIR}")
print(f"  目标峰值: {TARGET_PEAK} RPM")
print()


# ============================================================
# 步骤 1 + 1.5（合并）：直接从 downloaded JSONL 构建日期分片 CSV
# ============================================================
# downloaded JSONL 格式：每行是 list of message dicts
#   role='b': 用户消息，含 time 时间戳（ms）
#   role='a': 模型回复，含 prompt（完整 messages JSON）和 content（回复内容）
#   role='ib': 内部数据注入（八字信息）
#
# 模型别名过滤：extra_data.ai_info.model in MODEL_LIST
# 输出列：income_time, prompt, messages, old_response, user_id, line_num
# ============================================================
INDEX_FILE = Path(OUTPUT_DIR) / f"{MODEL_NAME}_all.csv"
day_csvs_check = sorted(Path(OUTPUT_DIR).glob(f"{MODEL_NAME}_2[0-9][0-9][0-9]-*.csv"))

if day_csvs_check:
    print(f"步骤1+1.5: 检测到已有日期分片 {len(day_csvs_check)} 个，跳过转换")
    for p in day_csvs_check:
        df_tmp = pd.read_csv(p)
        print(f"  {p.name}: {len(df_tmp):,} 行")
    print()
else:
    print("=" * 60)
    print("步骤1+1.5: 直接从 downloaded JSONL 构建日期分片 CSV（50k 对话）")
    print("=" * 60)

    import datetime as dt_module

    MODEL_LIST_SET = set(MODEL_LIST)
    rows_by_day: dict[str, list] = {}
    skip_no_prompt = 0
    skip_no_model = 0
    total_processed = 0

    with open(JSONL_FILE, encoding="utf-8") as jf:
        for idx, raw in enumerate(jf):
            line_num = idx + 1
            try:
                msgs = json.loads(raw.strip())
                if not isinstance(msgs, list):
                    continue

                # 找最后一条 role='a' 消息（含 prompt 字段）
                assistant_msg = None
                for m in reversed(msgs):
                    if m.get("role") == "a" and m.get("prompt"):
                        ai_info = m.get("extra_data", {}).get("ai_info", {})
                        model_val = ai_info.get("model") or ai_info.get("suffix") or ""
                        if model_val in MODEL_LIST_SET:
                            assistant_msg = m
                            break

                if assistant_msg is None:
                    skip_no_model += 1
                    continue

                # 找第一条 role='b' 用户消息（取时间戳）
                user_msg = next((m for m in msgs if m.get("role") == "b"), None)
                if user_msg is None or not user_msg.get("time"):
                    skip_no_prompt += 1
                    continue

                # 转换时间戳
                ts_ms = user_msg["time"]
                income_dt = dt_module.datetime.fromtimestamp(
                    ts_ms / 1000,
                    tz=dt_module.timezone(dt_module.timedelta(hours=8))
                ).replace(tzinfo=None)
                income_time_str = income_dt.strftime("%Y-%m-%d %H:%M:%S")
                day_key = income_dt.strftime("%Y-%m-%d")

                # 提取 messages 和 old_response
                messages_str = assistant_msg.get("prompt", "")
                old_response = assistant_msg.get("content", "") or ""
                user_id = user_msg.get("_id", "") or ""

                row = {
                    "income_time": income_time_str,
                    "prompt": "",
                    "messages": messages_str,
                    "old_response": old_response,
                    "user_id": user_id,
                    "line_num": line_num,
                }
                rows_by_day.setdefault(day_key, []).append(row)
                total_processed += 1

            except (json.JSONDecodeError, KeyError, TypeError):
                pass

    print(f"  处理完成: 总处理 {total_processed:,} 条")
    print(f"  跳过（无匹配模型别名）: {skip_no_model:,}")
    print(f"  跳过（无时间戳）: {skip_no_prompt:,}")
    print(f"  按天分布:")

    OUTPUT_COLS = ["income_time", "prompt", "messages", "old_response", "user_id", "line_num"]
    all_dfs = []
    for day_key in sorted(rows_by_day.keys()):
        df_day = pd.DataFrame(rows_by_day[day_key], columns=OUTPUT_COLS)
        df_day = df_day.sort_values("income_time").reset_index(drop=True)
        day_csv = Path(OUTPUT_DIR) / f"{MODEL_NAME}_{day_key}.csv"
        df_day.to_csv(day_csv, index=False)
        print(f"    {day_csv.name}: {len(df_day):,} 行")
        all_dfs.append(df_day)

    # 合并全量 _all.csv
    df_full = pd.concat(all_dfs, ignore_index=True).sort_values("income_time").reset_index(drop=True)
    df_full["old_response"] = df_full["old_response"].fillna("")
    df_full.to_csv(INDEX_FILE, index=False)
    print(f"\n  全量 _all.csv: {len(df_full):,} 行  列: {list(df_full.columns)}")
    filled = (df_full["old_response"] != "").sum()
    print(f"  old_response 有效填充: {filled:,} / {len(df_full):,}  ({filled/len(df_full)*100:.1f}%)")
    print(f"✅ 步骤1+1.5 完成\n")


# ============================================================
# 步骤 2：按峰值窗口采样（直接 pandas 过滤，兼容自定义 CSV 格式）
# ============================================================
print("=" * 60)
print("步骤2: 数据采样（2个 20min 峰值窗口，直接 pandas 过滤）")
print("=" * 60)

# 读取全量数据（或按天分片读取，按需选择）
day_csvs = sorted(Path(OUTPUT_DIR).glob(f"{MODEL_NAME}_2[0-9][0-9][0-9]-*.csv"))
print(f"  读取日期分片: {[p.name for p in day_csvs]}")
df_all = pd.concat([pd.read_csv(p) for p in day_csvs], ignore_index=True)
df_all["income_time"] = pd.to_datetime(df_all["income_time"])
df_all = df_all.sort_values("income_time").reset_index(drop=True)
print(f"  全量记录数: {len(df_all):,}\n")

sampled_frames = []
for start_str, end_str, desc in PEAK_WINDOWS:
    start_dt = datetime.strptime(start_str, "%Y-%m-%d %H:%M:%S")
    end_dt   = datetime.strptime(end_str,   "%Y-%m-%d %H:%M:%S")
    print(f"  ▶ {desc}")
    print(f"    {start_str} ~ {end_str}")
    mask = (df_all["income_time"] >= start_dt) & (df_all["income_time"] <= end_dt)
    df_win = df_all[mask].copy().reset_index(drop=True)
    if len(df_win) == 0:
        print(f"    ⚠️  无数据，跳过")
        continue
    rpm = df_win["income_time"].dt.floor("min").value_counts()
    print(f"    ✅ 采样 {len(df_win):,} 条  峰值 RPM={rpm.max()}  均值 RPM={rpm.mean():.1f}\n")
    sampled_frames.append(df_win)

if not sampled_frames:
    print("\n❌ 所有窗口均无数据")
    sys.exit(1)

df_combined = pd.concat(sampled_frames, ignore_index=True)
df_combined["income_time"] = pd.to_datetime(df_combined["income_time"])
df_combined = df_combined.sort_values("income_time").reset_index(drop=True)

combined_file = str(Path(OUTPUT_DIR) / f"{MODEL_NAME}_selected_combined_2days_peak.csv")
df_combined.to_csv(combined_file, index=False)

rpm_c = df_combined["income_time"].dt.floor("min").value_counts()
print(f"\n合并采样结果:")
print(f"  总请求数: {len(df_combined):,}")
print(f"  峰值 RPM: {rpm_c.max()}")
print(f"  均值 RPM: {rpm_c.mean():.1f}")
print(f"  文件:     {Path(combined_file).name}\n")


# ============================================================
# 步骤 3：时间戳拼接（消除两段间 ~22h 大间隔）
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
    df_stitched.to_csv(stitched_file, index=False)

    diffs2 = df_stitched["income_time"].diff()
    remaining_gaps = diffs2[diffs2 > pd.Timedelta("5min")]
    print(f"  拼接后大间隔: {len(remaining_gaps)} 个")
    print(f"  拼接后总行数: {len(df_stitched):,}")
    print(f"  输出: {Path(stitched_file).name}")
    df_stitch = df_stitched

print()


# ============================================================
# 步骤 4：泊松流量插值 → 256 RPM
# ============================================================
print("=" * 60)
print(f"步骤4: 流量插值（目标峰值 {TARGET_PEAK} RPM）")
print("=" * 60)

from scripts.data_processor.config.settings import GlobalConfig
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
print(f"  输出: {Path(interpolated_file).name}\n")


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

df_clean.to_csv(interpolated_file, index=False)
print(f"  ✅ 已覆盖写回: {Path(interpolated_file).name}\n")


# ============================================================
# 步骤 6：写 README.md
# ============================================================
print("=" * 60)
print("步骤6: 写 README.md")
print("=" * 60)

readme_path = Path(OUTPUT_DIR) / "README.md"
total_rows = len(pd.read_csv(interpolated_file))
readme_content = f"""# {MODEL_NAME} 数据集 V2（真实线上数据）

## 数据来源
- 原始文件: `guoxue-v1-2-online-2026-01-1631-downloaded-s50k.jsonl`
- 原始行数: 50,000 条（2026-01-16 00:00 ~ 2026-01-17 23:58）
- 模型别名（model_list）: `{MODEL_LIST}`
- 处理日期: {datetime.now().strftime('%Y-%m-%d')}
- **⚠️ V1 使用兜底数据（system prompt="八字解读专家..."），V2 使用真实线上数据（system prompt="下面需要你扮演一个八字解读大师，名字叫小智..."）**

## 处理流程（6步管道）

| 步骤 | 操作 | 关键参数 |
|------|------|---------|
| 1 | JSONL → 日期分片 CSV | read_only_time=False，MODEL_LIST 含"八字深度"别名 |
| 1.5 | 合并分片 + 回填 old_response | role='a' content 字段 |
| 2 | 峰值窗口采样 | 01-16 00:00~00:20（峰值72RPM）+ 01-16 22:49~23:09（峰值55RPM）|
| 3 | 时间戳拼接 | 消除两段间 ~22h 间隔 |
| 4 | 泊松插值 | TARGET_PEAK={TARGET_PEAK} RPM（213+43，Grafana 两段峰值叠加）|
| 5 | 脏数据过滤 | 剔除 content 为 list 的行 |
| 6 | README.md | 本文档 |

## 核心交付文件

| 文件 | 类型 | 说明 |
|------|------|------|
| `{MODEL_NAME}_2026-01-16.csv` | 中间产物 | DataConverter 日期分片 |
| `{MODEL_NAME}_2026-01-17.csv` | 中间产物 | DataConverter 日期分片 |
| `{MODEL_NAME}_all.csv` | 中间产物 | 全量合并（步骤1.5 覆盖写回 6 列完整数据）|
| `{MODEL_NAME}_selected_combined_2days_peak.csv` | 中间产物 | 两段峰值采样合并（未拼接）|
| `{MODEL_NAME}_selected_combined_2days_peak_stitched.csv` | 中间产物 | 时间戳拼接后，连续序列 |
| **`{MODEL_NAME}_selected_combined_2days_peak_poisson_{TARGET_PEAK}_stitched.csv`** | **最终交付** | **压测使用此文件**，峰值 {TARGET_PEAK} RPM，{total_rows:,} 行 |
| `{MODEL_NAME}_poisson_{TARGET_PEAK}_compare.html` | 可视化 | 插值前后流量对比图 |

## 与 V1 的对比

| 项目 | V1（兜底数据）| V2（真实线上数据）|
|------|-------------|----------------|
| 数据来源 | 260313_260314.jsonl（23,361行）| downloaded-s50k.jsonl（50,000行）|
| system prompt | "八字解读专家..." | "下面需要你扮演一个八字解读大师，名字叫小智..." |
| 时间范围 | 2026-03-13~14 | 2026-01-16~17 |
| 模型别名 | xinghan-guoxue-72b-v1-2-reason | +八字深度 |
| Poisson 目标 | 220 RPM | 256 RPM |

## 验证结论
- model_list 别名验证：JSONL 中模型标识为"八字深度"（extra_data.ai_info.model），已纳入 MODEL_LIST
- 峰值窗口选择：01-16 00:02 最高峰 72 RPM，01-16 22:59 夜间峰 55 RPM
- 插值放大倍数：{TARGET_PEAK} / 72 ≈ {TARGET_PEAK/72:.1f}x（基于凌晨峰值）
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
