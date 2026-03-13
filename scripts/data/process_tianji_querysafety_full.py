#!/usr/bin/env python3
"""
tianji-querysafety-4b-v2-3 数据处理脚本
遵循 traffic-dataset-prep SKILL — 情况 B（CSV 源数据 + 系统提示模板填充）

数据来源: tianji-querysafety-4b-v2-3_26030320_26030402_Sheet1.csv
  字段: user_id / sessionid / times(ms, Asia/Shanghai) / query / result
  总行数: ~281,442
  时间范围: 2026-03-03 20:00 ~ 2026-03-04 02:00（约 6 小时）
  峰值 RPM: ~2168（集中于 03-04 00:00~01:00）

处理流程:
  步骤1: 读取 CSV，times(ms) → income_time（Asia/Shanghai，去时区）
  步骤2: 清洗 query（去空行），填充系统提示模板 {{query}} → messages JSON
  步骤3: 输出全量数据集 _all.csv
  步骤4: 峰值窗口采样（03-04 00:00 ~ 00:30，约 39,000 条）→ _peak30min.csv
  步骤5: 脏数据检查（content 为 list 类型，理论上不存在，做安全确认）

messages 格式说明:
  系统提示末尾含 {{query}} 占位符（第 429~431 行），
  整体作为 system message 内容，query 嵌入其中。
  messages = [{"role": "system", "content": "<filled_system_prompt>"}]
"""

import sys
import json
import ast
from pathlib import Path

import pandas as pd

# ============================================================
# 配置
# ============================================================
CSV_FILE        = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/tianji-querysafety-4b-v2-3_26030320_26030402_Sheet1.csv"
SYSTEM_PROMPT_FILE = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/tianji-querysafety-v2-3-system_prompt.txt"
OUTPUT_DIR      = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output_tianji_querysafety"
MODEL_NAME      = "tianji-querysafety-4b-v2-3"

# 峰值窗口（03-04 00:00 ~ 00:30，覆盖最高流量时段）
PEAK_START      = "2026-03-04 00:00:00"
PEAK_END        = "2026-03-04 00:30:00"

Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)

print("=" * 60)
print("tianji-querysafety-4b-v2-3 数据处理")
print("=" * 60)
print(f"  源数据:       {Path(CSV_FILE).name}")
print(f"  系统提示:     {Path(SYSTEM_PROMPT_FILE).name}")
print(f"  输出目录:     {OUTPUT_DIR}")
print()


# ============================================================
# 读取系统提示模板
# ============================================================
print("读取系统提示模板...")
system_prompt_template = Path(SYSTEM_PROMPT_FILE).read_text(encoding="utf-8")
if "{{query}}" not in system_prompt_template:
    print("❌ 系统提示中未找到 {{query}} 占位符，请检查文件")
    sys.exit(1)
print(f"  ✅ 模板长度: {len(system_prompt_template)} 字符，{{{{query}}}} 占位符已确认")
print()


# ============================================================
# 步骤1：读取 CSV，转换时间戳
# ============================================================
print("=" * 60)
print("步骤1: 读取 CSV，times(ms) → income_time")
print("=" * 60)

df = pd.read_csv(CSV_FILE, dtype={"times": str})
total_raw = len(df)
print(f"  原始行数: {total_raw:,}")

# times 字段：毫秒时间戳，转为 Asia/Shanghai 本地时间（去时区信息）
df["income_time"] = (
    pd.to_datetime(df["times"].str.strip().astype(float).astype("int64"), unit="ms", utc=True)
    .dt.tz_convert("Asia/Shanghai")
    .dt.tz_localize(None)
)
df = df.sort_values("income_time").reset_index(drop=True)

print(f"  时间范围: {df['income_time'].min()}  ~  {df['income_time'].max()}")
rpm_by_min = df["income_time"].dt.floor("min").value_counts()
print(f"  峰值 RPM: {rpm_by_min.max()}  (分钟: {rpm_by_min.idxmax()})")
print(f"  均值 RPM: {rpm_by_min.mean():.1f}")
print()


# ============================================================
# 步骤2：清洗 query，填充模板，构建 messages
# ============================================================
print("=" * 60)
print("步骤2: 清洗 query + 填充系统提示模板 → messages")
print("=" * 60)

# 去掉 query 为空或只有空白的行
before = len(df)
df = df[df["query"].notna() & df["query"].astype(str).str.strip().ne("")].reset_index(drop=True)
dropped_empty = before - len(df)
if dropped_empty > 0:
    print(f"  ⚠️  去除空 query 行: {dropped_empty} 行")

# 填充模板 → 构建 messages JSON 字符串
def build_messages(query: str) -> str:
    filled = system_prompt_template.replace("{{query}}", str(query).strip())
    messages = [{"role": "system", "content": filled}]
    return json.dumps(messages, ensure_ascii=False)

print("  填充模板中（每行 query → system message）...")
df["messages"] = df["query"].apply(build_messages)

# old_response: 保留原始模型输出，供对比用
df["old_response"] = df["result"].fillna("")

print(f"  ✅ messages 构建完成，共 {len(df):,} 行")
print(f"  示例（截断）: {df['messages'].iloc[0][:120]}...")
print()


# ============================================================
# 步骤3：输出全量数据集 _all.csv
# ============================================================
print("=" * 60)
print("步骤3: 输出全量数据集 _all.csv")
print("=" * 60)

OUTPUT_COLS = ["income_time", "prompt", "messages", "old_response", "query", "user_id"]
all_csv = Path(OUTPUT_DIR) / f"{MODEL_NAME}_all.csv"
df[OUTPUT_COLS].to_csv(all_csv, index=False)
print(f"  ✅ 已保存: {all_csv.name}  ({len(df):,} 行, {all_csv.stat().st_size/1024/1024:.1f} MB)")
print()


# ============================================================
# 步骤4：峰值窗口采样 → _peak30min.csv
# ============================================================
print("=" * 60)
print(f"步骤4: 峰值窗口采样 ({PEAK_START} ~ {PEAK_END})")
print("=" * 60)

df_peak = df[
    (df["income_time"] >= PEAK_START) &
    (df["income_time"] <= PEAK_END)
].reset_index(drop=True)

peak_csv = Path(OUTPUT_DIR) / f"{MODEL_NAME}_peak30min.csv"
df_peak[OUTPUT_COLS].to_csv(peak_csv, index=False)

rpm_peak = df_peak["income_time"].dt.floor("min").value_counts()
print(f"  采样行数: {len(df_peak):,}")
print(f"  峰值 RPM: {rpm_peak.max()}")
print(f"  均值 RPM: {rpm_peak.mean():.1f}")
print(f"  ✅ 已保存: {peak_csv.name}  ({peak_csv.stat().st_size/1024/1024:.1f} MB)")
print()


# ============================================================
# 步骤5：脏数据检查
# ============================================================
print("=" * 60)
print("步骤5: 脏数据检查（content 为 list 类型）")
print("=" * 60)

def has_list_content(messages_str: str) -> bool:
    try:
        msgs = json.loads(messages_str)
    except Exception:
        try:
            msgs = ast.literal_eval(messages_str)
        except Exception:
            return False
    return any(isinstance(m.get("content"), list) for m in msgs if isinstance(m, dict))

bad_mask = df["messages"].apply(has_list_content)
if bad_mask.sum() > 0:
    print(f"  ⚠️  发现脏行: {bad_mask.sum()} 行，过滤中...")
    df = df[~bad_mask].reset_index(drop=True)
    df[OUTPUT_COLS].to_csv(all_csv, index=False)
    print(f"  已覆盖写回 _all.csv: {len(df):,} 行")
else:
    print(f"  ✅ 未发现脏行（预期，messages 由模板构建）")
print()


# ============================================================
# 汇总
# ============================================================
print("=" * 60)
print("处理完成！输出文件:")
print("=" * 60)
for f in sorted(Path(OUTPUT_DIR).glob("*.csv")):
    print(f"  {f.name:<65}  {len(pd.read_csv(f)):>7,} 行  {f.stat().st_size/1024/1024:>6.1f} MB")
print()
print(f"  推荐压测数据集: {peak_csv.name}  ← 峰值 30min 窗口")
print(f"  全量数据集:     {all_csv.name}  ← 完整 6h 流量")
print("=" * 60)
