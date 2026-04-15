"""
重试下载 lingyu 峰值 CSV 中 messages 为空的行的 COS URL。
降低并发（20），增大超时（30s），分批写回，支持断点续传。
"""

import asyncio
import json
import sys
from pathlib import Path

import aiohttp
import pandas as pd

PEAK_CSV      = Path("datas/output_lingyu/lingyu-235b-A22b-v9-2_selected_peak_stitched.csv")
CONCURRENCY   = 20
TIMEOUT_SEC   = 30
BATCH_SIZE    = 500      # 每批写回一次
LOG_EVERY     = 200

async def fetch_one(session, url: str, idx: int) -> tuple[int, str]:
    if not url or not str(url).startswith("http"):
        return idx, ""
    try:
        async with session.get(
            url,
            timeout=aiohttp.ClientTimeout(total=TIMEOUT_SEC),
            ssl=False
        ) as resp:
            if resp.status == 200:
                return idx, await resp.text()
            return idx, ""
    except Exception:
        return idx, ""


async def main():
    print(f"📖 读取 {PEAK_CSV.name} ...")
    df = pd.read_csv(PEAK_CSV)
    total = len(df)

    empty_mask = df["messages"].fillna("").str.strip() == ""
    todo_idx   = df.index[empty_mask].tolist()
    print(f"   总行: {total:,}, messages 为空: {len(todo_idx):,}, 已有: {total - len(todo_idx):,}")

    if not todo_idx:
        print("✅ 已全部下载完毕，无需重试。")
        return

    urls = [(i, df.at[i, "prompt_url"]) for i in todo_idx]

    connector  = aiohttp.TCPConnector(limit=CONCURRENCY, ssl=False)
    success    = 0
    fail       = 0
    done_count = 0

    print(f"\n⬇️  开始重试下载（并发={CONCURRENCY}, 超时={TIMEOUT_SEC}s）...")

    async with aiohttp.ClientSession(connector=connector) as sess:
        # 分批处理，每 BATCH_SIZE 条写一次
        for batch_start in range(0, len(urls), BATCH_SIZE):
            batch = urls[batch_start : batch_start + BATCH_SIZE]
            tasks = [fetch_one(sess, url, idx) for idx, url in batch]
            results = await asyncio.gather(*tasks)

            for idx, text in results:
                if text.strip():
                    df.at[idx, "messages"] = text
                    success += 1
                else:
                    fail += 1
                done_count += 1

            # 每批写回
            df.to_csv(PEAK_CSV, index=False)

            if done_count % LOG_EVERY == 0 or done_count == len(urls):
                total_valid = (df["messages"].fillna("").str.strip() != "").sum()
                pct = total_valid / total * 100
                print(f"  进度 {done_count}/{len(urls)} | 累计成功 {success} 失败 {fail} | messages有效率 {pct:.1f}%")

    # 最终统计
    final_valid = (df["messages"].fillna("").str.strip() != "").sum()
    print(f"\n✅ 重试完成: 新增成功 {success}, 仍失败 {fail}")
    print(f"   最终 messages 有效率: {final_valid}/{total} ({final_valid/total:.1%})")
    df.to_csv(PEAK_CSV, index=False)
    print(f"   已写回 → {PEAK_CSV}")


if __name__ == "__main__":
    asyncio.run(main())
