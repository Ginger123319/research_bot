#!/usr/bin/env python3
"""
将 xinghan-chart-32b-v1-1-agent Agent 调用转化数据制备成 benchmark CSV。

Input:  datas/xinghan-chart-32b-v1-1-agent_calls_converted.jsonl
        每行 = [role_b, role_ib, role_a]，role_a["prompt"] 已由 convert_chart_agent_prompt2.py 填充

Output: datas/output_chart_agent/xinghan-chart-32b-v1-1-agent_all.csv
        列: income_time, prompt, messages, old_response, user_id, line_num

old_response 处理：
    - chart-32b 为非推理模型，无 ai_deep_content，只需 Step 1：<con>→## 结论
    - 不需要 Step 2（ai_deep_content 前置）

income_time: role_b["time"] (ms) → Asia/Shanghai
messages:    json.dumps(role_a["prompt"], ensure_ascii=False)
"""

import json
import re
import datetime
import ast
import sys
from pathlib import Path

import pandas as pd

BASE_DIR    = Path(__file__).resolve().parents[2]
INPUT_FILE  = BASE_DIR / "datas/xinghan-chart-32b-v1-1-agent_calls_converted.jsonl"
OUTPUT_DIR  = BASE_DIR / "datas/output_chart_agent"
MODEL_NAME  = "xinghan-chart-32b-v1-1-agent"
OUTPUT_CSV  = OUTPUT_DIR / f"{MODEL_NAME}_all.csv"

OUTPUT_COLS = ["income_time", "prompt", "messages", "old_response", "user_id", "line_num"]

TZ_CST = datetime.timezone(datetime.timedelta(hours=8))


def build_old_response_chart(content: str) -> str:
    """
    chart-32b 专用（非推理模型）：仅执行 Step 1，将 <con>...</con> 还原为 ## 结论。
    不处理 ai_deep_content（chart-32b 无推理链）。
    """
    m = re.search(r'<con>(.*?)</con>', content, re.DOTALL)
    if m:
        inner = m.group(1).strip().replace('## 请输入替换内容', '').strip()
        content = content[:m.start()] + f'## 结论\n{inner}' + content[m.end():]
    return content


def has_list_content(messages_val) -> bool:
    """检查 messages 中是否有 content 为 list 的脏行（多模态格式，benchmark 不支持）。"""
    if isinstance(messages_val, list):
        msgs = messages_val
    else:
        try:
            msgs = json.loads(messages_val)
        except Exception:
            try:
                msgs = ast.literal_eval(str(messages_val))
            except Exception:
                return False
    return any(isinstance(m.get("content"), list) for m in msgs if isinstance(m, dict))


def main():
    rows = []
    skip_no_prompt = 0
    skip_dirty = 0
    errors = 0

    print(f"读取: {INPUT_FILE}")
    with open(INPUT_FILE, encoding="utf-8") as f:
        for line_num, raw in enumerate(f, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
                if not isinstance(rec, list) or len(rec) < 3:
                    errors += 1
                    continue

                role_b = rec[0]
                role_a = rec[2]

                # ── income_time ────────────────────────────────────────────
                ts_ms = role_b.get("time")
                if not ts_ms:
                    errors += 1
                    continue
                income_dt = datetime.datetime.fromtimestamp(
                    ts_ms / 1000, tz=TZ_CST
                ).replace(tzinfo=None)

                # ── messages ───────────────────────────────────────────────
                prompt_list = role_a.get("prompt", [])
                if not prompt_list or not isinstance(prompt_list, list):
                    skip_no_prompt += 1
                    continue

                # 脏数据过滤：content 为 list 的多模态行
                if has_list_content(prompt_list):
                    skip_dirty += 1
                    continue

                messages_str = json.dumps(prompt_list, ensure_ascii=False)

                # ── old_response ───────────────────────────────────────────
                raw_content = role_a.get("content", "") or ""
                old_resp = build_old_response_chart(raw_content)

                # ── user_id ────────────────────────────────────────────────
                user_id = role_b.get("_id", "")

                rows.append({
                    "income_time": income_dt.strftime("%Y-%m-%d %H:%M:%S"),
                    "prompt":      "",
                    "messages":    messages_str,
                    "old_response": old_resp,
                    "user_id":     user_id,
                    "line_num":    line_num,
                })

            except Exception as e:
                errors += 1
                if errors <= 5:
                    print(f"  [line {line_num}] 解析异常: {e}", file=sys.stderr)

    print(f"\n解析完成：有效={len(rows):,}  无 prompt={skip_no_prompt:,}  脏行={skip_dirty:,}  异常={errors:,}")

    # ── 排序 + 写 CSV ──────────────────────────────────────────────────────
    df = pd.DataFrame(rows, columns=OUTPUT_COLS)
    df = df.sort_values("income_time").reset_index(drop=True)

    # ── 验证 ───────────────────────────────────────────────────────────────
    old_resp_nonempty = (df["old_response"] != "").mean()
    con_residual = df["old_response"].str.contains(r"<con>", regex=False).mean()
    print(f"old_response 非空率:  {old_resp_nonempty:.1%}")
    print(f"<con> 残留率:         {con_residual:.1%}  (应 ≈ 0%)")

    df.to_csv(OUTPUT_CSV, index=False)
    print(f"\n输出: {OUTPUT_CSV}  ({len(df):,} 行)")

    # ── 时间范围 ───────────────────────────────────────────────────────────
    df["_dt"] = pd.to_datetime(df["income_time"])
    print(f"时间范围: {df['_dt'].min()} ~ {df['_dt'].max()}")

    # ── 按日期分片 CSV（DataSampler 兼容，peak 采样备用）─────────────────
    df["_date"] = df["_dt"].dt.strftime("%Y-%m-%d")
    for date, grp in df.groupby("_date"):
        day_csv = OUTPUT_DIR / f"{MODEL_NAME}_{date}.csv"
        grp.drop(columns=["_dt", "_date"]).reset_index(drop=True).to_csv(day_csv, index=False)
    print(f"按日期分片写入: {df['_date'].nunique()} 个文件")

    # ── 每分钟 RPM 峰值 ────────────────────────────────────────────────────
    rpm_series = df["_dt"].dt.floor("min").value_counts()
    print(f"\n峰值 RPM: {rpm_series.max()}  (出现在 {rpm_series.idxmax()})")
    print(f"均值 RPM: {rpm_series.mean():.1f}")


if __name__ == "__main__":
    main()
