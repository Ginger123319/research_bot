#!/usr/bin/env python3
"""
xinghan-chart-32b-v1-1-agent 数据处理脚本（v3）

【背景】
  chart JSONL 是索引文件（每条记录的 messages/raw_content 是 COS URL 引用），
  与 guoxue/ziwei JSONL（messages 内联 list）格式不同，DataConverter 无法直接处理。

【两阶段处理】
  阶段1: 下载（download_by_indices.py）
    - 读索引 JSONL 的 raw_content URL → 多线程下载
    - 输出: downloaded_raw.jsonl（每行是 JSON array: [role=b, role=ib, role=a]）
    - role=a.prompt = 内联 list（系统提示+用户消息）- 已确认

  阶段2: 本脚本 - 转换 + 过滤
    - 读 downloaded_raw.jsonl → 过滤模型别名 → 构建 6 列 _all.csv
    - 脏数据过滤（content 为 list 的行）
    - README.md
    - QPS benchmark 直接使用 _all.csv（不需要峰值采样/插值，那是 replay 测试用的）

【列映射】
  income_time  ← data[0].time (ms → Asia/Shanghai 无时区字符串)
  prompt       ← "" (benchmark 工具要求此列存在)
  messages     ← json.dumps(data[-1].prompt)  (role=a 的 prompt list)
  old_response ← data[-1].content
  user_id      ← data[-1]._source_id  (downloader 写入的原索引 ID)
  line_num     ← 行号
"""

import sys, os, json, ast
from pathlib import Path
from datetime import datetime, timezone, timedelta
import pandas as pd

OUTPUT_DIR       = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output_chart"
MODEL_NAME       = "xinghan-chart-32b-v1-1-agent"
MODEL_LIST       = {"xinghan-chart-32b-v1-1-agent", "星盘普通"}
DOWNLOADED_JSONL = Path(OUTPUT_DIR) / "xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl"
ALL_CSV          = Path(OUTPUT_DIR) / f"{MODEL_NAME}_all.csv"
TZ_CN            = timezone(timedelta(hours=8))

os.makedirs(OUTPUT_DIR, exist_ok=True)

print("=" * 60)
print("xinghan-chart-32b-v1-1-agent 转换处理（v3）")
print("=" * 60)
print(f"  输入: {DOWNLOADED_JSONL.name}")
print(f"  输出: {ALL_CSV.name}")
print(f"  模型别名: {MODEL_LIST}")
print()

if not DOWNLOADED_JSONL.exists():
    print(f"❌ 下载文件不存在: {DOWNLOADED_JSONL}")
    print("   请先运行阶段1下载脚本")
    sys.exit(1)


# ============================================================
# 步骤1: 读取 downloaded_raw.jsonl → 构建 rows
# ============================================================
print("[步骤1] 读取 downloaded_raw.jsonl → 构建 _all.csv")

rows = []
skipped_model = 0
skipped_no_prompt = 0
skipped_bad_json = 0
total_lines = 0

with open(DOWNLOADED_JSONL, "r", encoding="utf-8") as f:
    for line_num, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        total_lines += 1

        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            skipped_bad_json += 1
            continue

        if not isinstance(data, list) or len(data) < 2:
            skipped_bad_json += 1
            continue

        # 找最后一个 role=a
        last_a = next((m for m in reversed(data) if isinstance(m, dict) and m.get("role") == "a"), None)
        if not last_a:
            skipped_no_prompt += 1
            continue

        # 过滤模型别名
        model = last_a.get("extra_data", {}).get("ai_info", {}).get("model", "")
        if model not in MODEL_LIST:
            skipped_model += 1
            continue

        # 获取 prompt（内联 list）
        prompt_val = last_a.get("prompt", "")
        if not isinstance(prompt_val, list) or not prompt_val:
            skipped_no_prompt += 1
            continue

        # 取时间：优先用 role=b 的 time，回退用 role=a 的 time
        first_b = next((m for m in data if isinstance(m, dict) and m.get("role") == "b"), None)
        time_ms = (first_b.get("time") if first_b else None) or last_a.get("time")
        if not time_ms:
            skipped_no_prompt += 1
            continue

        income_dt = datetime.fromtimestamp(int(time_ms) / 1000, tz=TZ_CN).replace(tzinfo=None)

        rows.append({
            "income_time":  income_dt.strftime("%Y-%m-%d %H:%M:%S"),
            "prompt":       "",
            "messages":     json.dumps(prompt_val, ensure_ascii=False),
            "old_response": str(last_a.get("content", "")),
            "user_id":      str(last_a.get("_source_id", "")),
            "line_num":     line_num,
        })

print(f"  总行数:         {total_lines:,}")
print(f"  有效行数:       {len(rows):,}")
print(f"  跳过-模型不符:  {skipped_model:,}")
print(f"  跳过-无prompt:  {skipped_no_prompt:,}")
print(f"  跳过-JSON错误:  {skipped_bad_json:,}")
print()

if not rows:
    print("❌ 无有效数据，请检查 downloaded_raw.jsonl 内容和模型别名")
    sys.exit(1)


# ============================================================
# 步骤2: 脏数据过滤（content 为 list 的行）
# ============================================================
print("[步骤2] 脏数据过滤（剔除 content 为 list 的行）")

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

df = pd.DataFrame(rows)
df["income_time"] = pd.to_datetime(df["income_time"])
df = df.sort_values("income_time").reset_index(drop=True)

before = len(df)
mask = df["messages"].apply(has_list_content)
df = df[~mask].reset_index(drop=True)
removed = before - len(df)
print(f"  过滤前: {before:,} 行  →  过滤后: {len(df):,} 行  (删除 {removed} 脏行)")
print()


# ============================================================
# 步骤3: 保存 _all.csv
# ============================================================
print("[步骤3] 保存 _all.csv")

# 验证数据完整性
non_empty_msg = df["messages"].dropna().str.strip().ne("").sum()
rpm = df["income_time"].dt.floor("min").value_counts()
print(f"  总行数:           {len(df):,}")
print(f"  messages 有内容:  {non_empty_msg:,} / {len(df):,}")
print(f"  峰值 RPM:         {rpm.max()}")
print(f"  时间范围:         {df['income_time'].min()} ~ {df['income_time'].max()}")

# 检查 QPS sweep 最低需求：QPS=4.0 × 2700s = 10800 条
min_needed = int(4.0 * 2700)
if len(df) < min_needed:
    print(f"  ⚠️  行数 {len(df):,} 可能不足（QPS=4.0 至少需要 {min_needed:,} 条）")
else:
    print(f"  ✅ 行数充足（QPS=4.0 至少需要 {min_needed:,} 条）")

df.to_csv(ALL_CSV, index=False)
print(f"  已写入: {ALL_CSV}  ({ALL_CSV.stat().st_size:,} bytes)")
print()


# ============================================================
# 步骤4: README.md
# ============================================================
print("[步骤4] 写 README.md")

readme_path = Path(OUTPUT_DIR) / "README.md"
readme_content = f"""# {MODEL_NAME} 数据集

## 数据来源
- 索引文件: `xinghan-chart-32b-v1-1-agent_260312_260316.jsonl`（47,338 条索引）
- 下载文件: `xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl`（从 raw_content URL 下载）
- 模型别名（model_list）: `{MODEL_LIST}`
- 处理日期: {datetime.now().strftime('%Y-%m-%d')}
- 处理脚本: `scripts/data/process_chart_full_v3.py`

## 格式说明（与 guoxue/ziwei 的区别）
chart JSONL 是索引文件，messages 字段为 COS URL。需要先用 `download_by_indices.py`
下载 raw_content URL 得到实际数据（每行是 JSON array，role=a.prompt 为内联 list）。

## 处理流程
1. 下载: `download_by_indices.py` → `downloaded_raw.jsonl`（多线程，断点续传）
2. 转换: 本脚本 → 过滤模型别名 → 构建 6 列 _all.csv
3. 脏数据过滤: 删除 content 为 list 的行

## 产出文件

| 文件 | 说明 |
|------|------|
| `xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl` | 下载的原始数据（每行 JSON array） |
| **`{MODEL_NAME}_all.csv`** | **QPS benchmark 使用此文件** |
| `README.md` | 本文档 |

## 数据统计
- 下载总行数: {total_lines:,}
- 有效行数（模型匹配）: {before:,}
- 过滤后最终行数: {len(df):,}
- 时间范围: {df['income_time'].min()} ~ {df['income_time'].max()}
- 峰值 RPM: {rpm.max()}

## QPS Benchmark 使用
QPS benchmark 直接使用 `_all.csv`（无需峰值采样/插值，replay 测试才需要）。
最高档 QPS=4.0 × 2700s = 10,800 条，数据集 {len(df):,} 条，充足。

```bash
# 8TP 部署
nohup bash scripts/benchmark/run_chart_8tp_qps_sweep.sh \\
    > logs/data-pipeline/chart_8tp_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# 4TP 部署（对照实验）
nohup bash scripts/benchmark/run_chart_4tp_qps_sweep.sh \\
    > logs/data-pipeline/chart_4tp_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```
"""
readme_path.write_text(readme_content, encoding="utf-8")
print(f"  ✅ {readme_path}")
print()

print("=" * 60)
print("✅ 转换处理完成！")
print("=" * 60)
print(f"benchmark 数据集: {ALL_CSV}")
print(f"最终行数: {len(df):,}")
