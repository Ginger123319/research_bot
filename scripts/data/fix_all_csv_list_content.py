#!/usr/bin/env python3
"""
修复 xinghan-ziwei-32b-v1-1_all.csv 中 messages.content 为 list 类型的脏行。

根因：部分请求使用多模态格式（content 为 list 而非 str），
      benchmark 在 apply_chat_template 时 Jinja 模板做字符串拼接报错：
      TypeError: can only concatenate str (not "list") to str

修复逻辑：检测并过滤这些行，其余数据保持不变，覆盖写回原文件。
"""

import ast
import json
import sys
from pathlib import Path

import pandas as pd

ALL_CSV = Path("/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output"
               "/xinghan-ziwei-32b-v1-1_all.csv")


def has_list_content(messages_str: str) -> bool:
    """判断 messages 字符串中是否存在 content 为 list 类型的消息。"""
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


print("=" * 60)
print("_all.csv 脏数据修复（content 为 list 类型的行）")
print("=" * 60)

if not ALL_CSV.exists():
    print(f"❌ 文件不存在: {ALL_CSV}")
    sys.exit(1)

print(f"  读取: {ALL_CSV.name}  ...", flush=True)
df = pd.read_csv(ALL_CSV)
total_before = len(df)
print(f"  读取完成，共 {total_before:,} 行")

print("  检测 list content 脏行 ...", flush=True)
mask = df["messages"].apply(has_list_content)
bad_count = mask.sum()

if bad_count == 0:
    print("✅ 未发现脏行，文件无需修改。")
    sys.exit(0)

print(f"  发现脏行: {bad_count} 行（索引: {list(df.index[mask])}）")

df_clean = df[~mask].reset_index(drop=True)
total_after = len(df_clean)

print(f"  过滤后剩余: {total_after:,} 行（移除 {bad_count} 行）")
print(f"  写回: {ALL_CSV.name}  ...", flush=True)
df_clean.to_csv(ALL_CSV, index=False)

print()
print(f"✅ 修复完成！{total_before:,} → {total_after:,} 行，已覆盖写回原文件。")
print("=" * 60)
