"""
lingyu-235b-A22b-v9-2 数据处理脚本
数据格式：session-based JSONL，每行是一个多轮对话 session（非标准情况A/C）

处理流程：
  步骤1   : 解析所有 session → turns，提取 income_time/old_response/prompt_url
  步骤1.5 : 写 _all.csv（无 messages，用于流量分析）+ 日期分片 CSV
  步骤2   : 峰值窗口采样
  步骤3   : 并发下载 COS URL 获取 messages → 写峰值 CSV（含 messages）
  步骤4   : 时间戳拼接
  步骤5   : 水尺判断 + 泊松插值（如需）
  步骤6   : 脏数据过滤
"""

import asyncio
import datetime as dt
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

import aiohttp
import pandas as pd

# ── 配置 ────────────────────────────────────────────────────────────────
JSONL_FILE    = "datas/lingyu_20260314_0316.jsonl"
OUTPUT_DIR    = Path("datas/output_lingyu")
MODEL_NAME    = "lingyu-235b-A22b-v9-2"
MODEL_SET     = {"lingyu-235b-A22b-v9-2"}

# 峰值窗口（步骤2，根据探查结果：22:30~23:10 为高峰）
PEAK_WINDOWS = [
    ("2026-03-14 22:30:00", "2026-03-14 23:10:00", "夜间峰值"),
]

# 并发下载参数
DOWNLOAD_CONCURRENCY = 100
DOWNLOAD_TIMEOUT     = 15

OUTPUT_COLS = ["income_time", "prompt", "messages", "old_response", "user_id", "prompt_url"]

# ── 工具函数 ──────────────────────────────────────────────────────────────

def build_old_response(content: str, ai_deep_content: str) -> str:
    """还原推理模型输出格式（lingyu 无推理链，通常只执行 Step 1）"""
    import re as _re
    m = _re.search(r'<con>(.*?)</con>', content, _re.DOTALL)
    if m:
        inner = m.group(1).strip().replace('## 请输入替换内容', '').strip()
        content = content[:m.start()] + f'## 结论\n{inner}' + content[m.end():]
    if ai_deep_content and ai_deep_content.strip():
        content = f'<think>{ai_deep_content.strip()}</think>\n\n' + content
    return content


def has_list_content(messages_str: str) -> bool:
    """检测 content 为 list 的脏行（多模态）"""
    try:
        msgs = json.loads(messages_str)
    except Exception:
        return False
    return any(isinstance(m.get("content"), list) for m in msgs if isinstance(m, dict))


# ── 步骤1+1.5：解析 session → turns ──────────────────────────────────────

def step1_extract_turns() -> pd.DataFrame:
    print("═" * 60)
    print("步骤1: 解析 session → turns ...")
    rows = []
    skipped = 0

    with open(JSONL_FILE, encoding="utf-8") as jf:
        for line_idx, raw in enumerate(jf):
            try:
                session = json.loads(raw.strip())
            except json.JSONDecodeError:
                continue

            msgs = session.get("messages", [])
            if not isinstance(msgs, list):
                continue

            user_id = session.get("user_id", "")

            for j, m in enumerate(msgs):
                if not isinstance(m, dict) or m.get("role") != "a":
                    continue

                # 模型别名过滤
                ai_info = m.get("extra_data", {}).get("ai_info", {})
                model_val = ai_info.get("model") or ai_info.get("suffix") or ""
                if model_val not in MODEL_SET:
                    continue

                # income_time：找前一条 role='b' 的 time
                user_time = None
                for bm in reversed(msgs[:j]):
                    if isinstance(bm, dict) and bm.get("role") == "b" and bm.get("time"):
                        user_time = bm["time"]
                        break
                if not user_time:
                    user_time = session.get("session_time") or session.get("create_time")
                if not user_time:
                    skipped += 1
                    continue

                income_dt = dt.datetime.fromtimestamp(
                    user_time / 1000,
                    tz=dt.timezone(dt.timedelta(hours=8))
                ).replace(tzinfo=None)

                # old_response
                raw_content     = m.get("content", "") or ""
                ai_deep_content = m.get("ai_deep_content", "") or ""
                old_resp = build_old_response(raw_content, ai_deep_content)

                # prompt_url（role='a' 的 prompt COS URL）
                prompt_url = m.get("prompt", "") or m.get("prompt2", "") or ""
                if not str(prompt_url).startswith("http"):
                    prompt_url = ""

                rows.append({
                    "income_time": income_dt.strftime("%Y-%m-%d %H:%M:%S"),
                    "prompt":      "",
                    "messages":    "",            # 留空，步骤3 填充
                    "old_response": old_resp,
                    "user_id":     user_id,
                    "prompt_url":  prompt_url,
                })

            if (line_idx + 1) % 500 == 0:
                print(f"  处理 {line_idx+1:,} sessions, 已提取 {len(rows):,} turns ...", end="\r")

    print(f"\n  完成：{len(rows):,} turns，跳过（无时间戳）{skipped}")

    df = pd.DataFrame(rows, columns=OUTPUT_COLS)
    df = df.sort_values("income_time").reset_index(drop=True)
    df["date"] = pd.to_datetime(df["income_time"]).dt.strftime("%Y-%m-%d")

    # ── 写日期分片 CSV（含 prompt_url，不含 messages）──────────────────
    print("步骤1.5: 写日期分片 CSV ...")
    all_dfs = []
    for date_key, group in df.groupby("date"):
        chunk = group.drop(columns=["date"]).reset_index(drop=True)
        out_path = OUTPUT_DIR / f"{MODEL_NAME}_{date_key}.csv"
        chunk.to_csv(out_path, index=False)
        all_dfs.append(chunk)
        print(f"  {out_path.name}: {len(chunk):,} turns")

    # ── 写 _all.csv（无 messages 列，仅流量分析用）───────────────────────
    df_all = pd.concat(all_dfs, ignore_index=True).sort_values("income_time").reset_index(drop=True)
    all_csv = OUTPUT_DIR / f"{MODEL_NAME}_all.csv"
    df_all.to_csv(all_csv, index=False)
    print(f"  _all.csv: {len(df_all):,} turns → {all_csv}")

    # 峰值 RPM 验证
    df_all["_dt"] = pd.to_datetime(df_all["income_time"])
    rpm_max = df_all["_dt"].dt.floor("min").value_counts().max()
    print(f"  全量峰值 RPM: {rpm_max}")

    return df_all


# ── 步骤2：峰值窗口采样 ────────────────────────────────────────────────────

def step2_sample_peak(df_all: pd.DataFrame) -> pd.DataFrame:
    print("═" * 60)
    print("步骤2: 峰值窗口采样 ...")
    df_all["_dt"] = pd.to_datetime(df_all["income_time"])
    frames = []
    for start_str, end_str, desc in PEAK_WINDOWS:
        mask = (df_all["_dt"] >= start_str) & (df_all["_dt"] <= end_str)
        win = df_all[mask].copy().reset_index(drop=True)
        peak_rpm = win["_dt"].dt.floor("min").value_counts().max() if len(win) else 0
        print(f"  {desc} [{start_str} ~ {end_str}]: {len(win):,} turns, 峰值 {peak_rpm} RPM")
        frames.append(win)

    df_peak = pd.concat(frames, ignore_index=True).sort_values("income_time").reset_index(drop=True)
    peak_csv = OUTPUT_DIR / f"{MODEL_NAME}_selected_peak_raw.csv"
    df_peak.to_csv(peak_csv, index=False)
    print(f"  → 峰值原始 {len(df_peak):,} turns → {peak_csv.name}")
    return df_peak


# ── 步骤3：并发下载 COS URL 填充 messages ──────────────────────────────────

async def _fetch_one(session, url: str, idx: int) -> tuple[int, str]:
    if not url:
        return idx, ""
    try:
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=DOWNLOAD_TIMEOUT), ssl=False) as resp:
            if resp.status == 200:
                text = await resp.text()
                return idx, text
            return idx, ""
    except Exception:
        return idx, ""


async def _download_all(urls: list[str]) -> list[str]:
    results = [""] * len(urls)
    connector = aiohttp.TCPConnector(limit=DOWNLOAD_CONCURRENCY, ssl=False)
    async with aiohttp.ClientSession(connector=connector) as sess:
        tasks = [_fetch_one(sess, url, i) for i, url in enumerate(urls)]
        done = 0
        for coro in asyncio.as_completed(tasks):
            idx, text = await coro
            results[idx] = text
            done += 1
            if done % 500 == 0:
                print(f"    下载进度: {done}/{len(urls)}", end="\r", flush=True)
    print()
    return results


def step3_download_messages(df_peak: pd.DataFrame) -> pd.DataFrame:
    print("═" * 60)
    total = len(df_peak)
    has_url = df_peak["prompt_url"].str.startswith("http", na=False).sum()
    print(f"步骤3: 下载 messages（{has_url}/{total} 条有 COS URL，并发 {DOWNLOAD_CONCURRENCY}）...")

    urls = df_peak["prompt_url"].fillna("").tolist()
    messages_list = asyncio.run(_download_all(urls))

    df_peak = df_peak.copy()
    df_peak["messages"] = messages_list

    ok = sum(1 for m in messages_list if m.strip())
    print(f"  下载成功: {ok}/{total} ({ok/total:.1%})")
    return df_peak


# ── 步骤4：时间戳拼接 ─────────────────────────────────────────────────────

def step4_stitch(df: pd.DataFrame) -> pd.DataFrame:
    print("═" * 60)
    print("步骤4: 时间戳拼接（消除段间 >5min 大间隔）...")
    df = df.copy()
    df["_dt"] = pd.to_datetime(df["income_time"])
    df = df.sort_values("_dt").reset_index(drop=True)

    diffs = df["_dt"].diff()
    big_gaps = diffs[diffs > pd.Timedelta("5min")]
    print(f"  大间隔（>5min）数量: {len(big_gaps)}")

    if len(big_gaps) > 0:
        # 找分段
        seg_starts = [0] + list(big_gaps.index)
        seg_ends   = list(big_gaps.index) + [len(df)]
        seg_ranges = list(zip(seg_starts, seg_ends))

        print(f"  段数: {len(seg_ranges)}")
        anchor_end = None
        segs = []
        for i, (s, e) in enumerate(seg_ranges):
            seg = df.iloc[s:e].copy()
            if i == 0:
                anchor_end = seg["_dt"].iloc[-1]
            else:
                offset = (anchor_end + pd.Timedelta("1s")) - seg["_dt"].iloc[0]
                seg["_dt"] = seg["_dt"] + offset
                anchor_end = seg["_dt"].iloc[-1]
            segs.append(seg)
        df = pd.concat(segs, ignore_index=True).sort_values("_dt").reset_index(drop=True)
    else:
        print("  无大间隔，无需拼接 ✅")

    df["income_time"] = df["_dt"].dt.strftime("%Y-%m-%d %H:%M:%S")
    df = df.drop(columns=["_dt"], errors="ignore")

    # 验证
    df2 = df.copy()
    df2["_dt"] = pd.to_datetime(df2["income_time"])
    remaining = (df2["_dt"].diff() > pd.Timedelta("5min")).sum()
    print(f"  拼接后大间隔数: {remaining} ✅" if remaining == 0 else f"  ⚠️  仍有 {remaining} 个大间隔")

    stitched_csv = OUTPUT_DIR / f"{MODEL_NAME}_selected_peak_stitched.csv"
    df.to_csv(stitched_csv, index=False)
    peak_rpm = pd.to_datetime(df["income_time"]).dt.floor("min").value_counts().max()
    print(f"  → {stitched_csv.name}: {len(df):,} turns, 峰值 {peak_rpm} RPM")
    return df, peak_rpm


# ── 步骤5：脏数据过滤 ─────────────────────────────────────────────────────

def step5_filter(df: pd.DataFrame, source_csv: Path) -> pd.DataFrame:
    print("═" * 60)
    print("步骤5: 脏数据过滤（content=list 多模态行）...")
    before = len(df)
    mask = df["messages"].fillna("").apply(
        lambda s: not has_list_content(s) if s.strip() else True
    )
    df = df[mask].reset_index(drop=True)
    removed = before - len(df)
    print(f"  移除 {removed} 条 → 剩余 {len(df):,} 条")
    df.to_csv(source_csv, index=False)
    print(f"  → 覆盖写回: {source_csv.name}")
    return df


# ── 主流程 ─────────────────────────────────────────────────────────────────

def main():
    OUTPUT_DIR.mkdir(exist_ok=True)
    print(f"📂 输出目录: {OUTPUT_DIR}")
    print(f"📄 源文件: {JSONL_FILE}")
    print()

    # 步骤 1+1.5
    df_all = step1_extract_turns()

    # 步骤 2
    df_peak_raw = step2_sample_peak(df_all)

    # 步骤 3
    df_peak = step3_download_messages(df_peak_raw)

    # 步骤 4
    df_stitched, peak_rpm = step4_stitch(df_peak)

    # 步骤 5 - 过滤峰值文件
    stitched_csv = OUTPUT_DIR / f"{MODEL_NAME}_selected_peak_stitched.csv"
    df_final = step5_filter(df_stitched, stitched_csv)

    print()
    print("═" * 60)
    print("✅ 处理完成！核心文件：")
    print(f"  _all.csv（全量流量分析）: {len(df_all):,} turns")
    print(f"  _selected_peak_stitched.csv（峰值 benchmark 数据）: {len(df_final):,} turns, 峰值 {peak_rpm} RPM")
    print(f"  messages 有效率: {df_final['messages'].str.strip().ne('').mean():.1%}")


if __name__ == "__main__":
    main()
