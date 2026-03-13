#!/usr/bin/env python3
"""
xinghan-ziwei-32b-v1-1 全量数据合并脚本（单实例压力测试用）

说明：
  按天 CSV（2026-03-03 ~ 2026-03-06）已是 JSONL 全量数据经 read_only_time=False
  转换的结果（多轮对话拆成单轮，故行数略多于 JSONL 原始行数）。
  本脚本直接将这 4 个按天文件合并为单文件 _all.csv，保留所有列，
  按 income_time 排序，供单实例压力测试直接使用，不做任何峰值窗口过滤。
"""

import ast
import json
import sys
from pathlib import Path
import pandas as pd


def has_list_content(messages_str: str) -> bool:
    """判断 messages 字符串中是否存在 content 为 list 类型的消息（多模态格式）。"""
    if not isinstance(messages_str, str) or not messages_str.strip():
        return False
    try:
        msgs = json.loads(messages_str)
    except (json.JSONDecodeError, ValueError):
        try:
            msgs = ast.literal_eval(messages_str)
        except Exception:
            return False
    if not isinstance(msgs, list):
        return False
    return any(isinstance(m.get("content"), list) for m in msgs if isinstance(m, dict))

OUTPUT_DIR = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output"
MODEL_NAME = "xinghan-ziwei-32b-v1-1"

ALL_CSV = Path(OUTPUT_DIR) / f"{MODEL_NAME}_all.csv"


def _find_day_csvs(output_dir: Path, model_name: str) -> list[Path]:
    """找到所有按天 CSV（排除 _all / _selected / _per_minute / _poisson 等衍生文件）"""
    found = []
    for f in output_dir.glob(f"{model_name}_*.csv"):
        name = f.name
        if any(tag in name for tag in ("_all.csv", "_selected_", "_per_minute",
                                        "_poisson_", "_stitched", "_traffic")):
            continue
        found.append(f)
    return sorted(found)


print("=" * 60)
print("紫微全量数据合并（单实例压力测试，无峰值窗口过滤）")
print("=" * 60)
print(f"  模型:     {MODEL_NAME}")
print(f"  输出目录: {OUTPUT_DIR}")
print(f"  目标文件: {ALL_CSV.name}")
print()

# ============================================================
# 合并全部按天 CSV → _all.csv（保留所有列）
# ============================================================
if ALL_CSV.exists():
    print(f"检测到已有 {ALL_CSV.name}，跳过合并")
    df_all = pd.read_csv(ALL_CSV)
    print(f"  已有记录数: {len(df_all):,}")
else:
    day_csvs = _find_day_csvs(Path(OUTPUT_DIR), MODEL_NAME)
    if not day_csvs:
        print("❌ 未找到任何按天 CSV，请先运行数据转换")
        sys.exit(1)

    print(f"找到 {len(day_csvs)} 个按天 CSV，开始合并...")
    frames = []
    for f in day_csvs:
        df = pd.read_csv(f)
        frames.append(df)
        print(f"  读取 {f.name}: {len(df):,} 行")

    df_all = pd.concat(frames, ignore_index=True)
    df_all["income_time"] = pd.to_datetime(df_all["income_time"])
    df_all = df_all.sort_values("income_time").reset_index(drop=True)

    # 过滤 messages.content 为 list 类型的多模态格式行（会导致 benchmark apply_chat_template 报错）
    bad_mask = df_all["messages"].apply(has_list_content)
    if bad_mask.sum() > 0:
        print(f"  ⚠️  过滤 content 为 list 的脏行: {bad_mask.sum()} 行")
        df_all = df_all[~bad_mask].reset_index(drop=True)

    df_all.to_csv(ALL_CSV, index=False)
    print(f"\n✅ 已保存: {ALL_CSV.name}  ({len(df_all):,} 行)")


# ============================================================
# 汇总统计
# ============================================================
print()
print("=" * 60)
print("全量数据统计")
print("=" * 60)

df_all["income_time"] = pd.to_datetime(df_all["income_time"])
rpm = df_all["income_time"].dt.floor("min").value_counts()
non_empty = df_all["messages"].dropna().str.strip().ne("").sum()

print(f"  总请求数:         {len(df_all):,}")
print(f"  时间范围:         {df_all['income_time'].min()}  ~  {df_all['income_time'].max()}")
print(f"  峰值 RPM:         {rpm.max()}")
print(f"  均值 RPM:         {rpm.mean():.2f}")
print(f"  messages 有内容:  {non_empty:,} / {len(df_all):,}")
print(f"  文件大小:         {ALL_CSV.stat().st_size:,} bytes  ({ALL_CSV.stat().st_size/1024/1024:.1f} MB)")
print()
print(f"  输出文件: {ALL_CSV}")
print("=" * 60)
