#!/usr/bin/env python3
"""
从 xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl 中提取 Agent 框架调用记录（41,320 条）。

过滤条件：role=a 元素中 extra_data.ai_info.model == "星盘普通"
输出格式：保留完整 JSON Array（3 个 role 全保留），每行一条
"""

import json
import sys
from pathlib import Path

INPUT_FILE = Path("/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl")
OUTPUT_FILE = Path("/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/xinghan-chart-32b-v1-1-agent_agent_calls_raw.jsonl")

TARGET_MODEL = "星盘普通"
TARGET_BOT_ID = "agen1754fc4ce3864211b572f4dc54d3"

def get_role_a(record):
    """从 JSON Array 中找到 role=a 的元素"""
    if not isinstance(record, list):
        return None
    for item in record:
        if isinstance(item, dict) and item.get("role") == "a":
            return item
    return None

def is_agent_call(role_a):
    """判断是否为 Agent 框架调用"""
    if role_a is None:
        return False
    ai_info = role_a.get("extra_data", {}).get("ai_info", {})
    model = ai_info.get("model", "")
    bot_id = ai_info.get("bot_id", "")
    return model == TARGET_MODEL or bot_id == TARGET_BOT_ID

def main():
    total = 0
    matched = 0
    skipped_parse_error = 0

    print(f"输入文件: {INPUT_FILE}")
    print(f"输出文件: {OUTPUT_FILE}")
    print("开始提取 Agent 框架调用记录...")

    with open(INPUT_FILE, "r", encoding="utf-8") as fin, \
         open(OUTPUT_FILE, "w", encoding="utf-8") as fout:

        for line_no, line in enumerate(fin, 1):
            total += 1
            line = line.strip()
            if not line:
                continue

            try:
                record = json.loads(line)
            except json.JSONDecodeError as e:
                skipped_parse_error += 1
                print(f"  [WARN] 第 {line_no} 行解析失败: {e}", file=sys.stderr)
                continue

            role_a = get_role_a(record)
            if is_agent_call(role_a):
                fout.write(json.dumps(record, ensure_ascii=False) + "\n")
                matched += 1

            if total % 5000 == 0:
                print(f"  已处理 {total:,} 行，已匹配 {matched:,} 条...")

    print(f"\n提取完成：")
    print(f"  总行数:         {total:,}")
    print(f"  Agent 框架记录: {matched:,}")
    print(f"  跳过（解析错误）: {skipped_parse_error}")
    print(f"  输出文件: {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
