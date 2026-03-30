"""
计算数据集 CSV 文件的输入/输出 token 分布统计，用于更新各子目录 README.md。

用法：
    python scripts/data/compute_token_stats.py \
        --csv datas/output_ziwei/xinghan-ziwei-32b-v1-1_all.csv \
        --tokenizer /mnt/ai-infra/models/Qwen2.5-72B-Instruct \
        [--sample 0.1]   # 大文件可采样，默认全量

输出：可直接粘贴到 README.md 的 Markdown 表格。
"""

import argparse
import json
import sys
import warnings

import numpy as np
import pandas as pd

warnings.filterwarnings("ignore")


def extract_text_from_messages(messages_str: str) -> str:
    """从 messages JSON 字符串中提取所有 content 文本拼接。"""
    if not isinstance(messages_str, str) or not messages_str.strip():
        return ""
    try:
        msgs = json.loads(messages_str)
        if not isinstance(msgs, list):
            return messages_str
        parts = []
        for m in msgs:
            if isinstance(m, dict):
                c = m.get("content", "")
                if isinstance(c, str):
                    parts.append(c)
                elif isinstance(c, list):
                    for item in c:
                        if isinstance(item, dict) and isinstance(item.get("text"), str):
                            parts.append(item["text"])
        return "\n".join(parts)
    except (json.JSONDecodeError, TypeError):
        return messages_str


def batch_tokenize(tokenizer, texts: list[str], batch_size: int = 512) -> list[int]:
    """批量 tokenize，返回每条文本的 token 数列表。"""
    counts = []
    total = len(texts)
    for i in range(0, total, batch_size):
        batch = texts[i : i + batch_size]
        encoded = tokenizer(batch, add_special_tokens=False, return_length=True)
        counts.extend(encoded["length"])
        if (i // batch_size) % 10 == 0:
            print(f"  tokenize 进度: {min(i + batch_size, total)}/{total}", end="\r", flush=True)
    print()
    return counts


def percentile_str(arr: np.ndarray, percentiles: list[int]) -> dict[str, float]:
    return {f"p{p}": float(np.percentile(arr, p)) for p in percentiles}


def fmt(v: float, is_int: bool = True) -> str:
    return str(int(round(v))) if is_int else f"{v:.1f}"


def compute_stats(csv_path: str, tokenizer_path: str, sample_frac: float | None = None):
    print(f"\n📂 CSV: {csv_path}")

    # ── 加载 tokenizer ──────────────────────────────────────────────
    print(f"🔤 加载 tokenizer: {tokenizer_path}")
    from transformers import AutoTokenizer
    tokenizer = AutoTokenizer.from_pretrained(tokenizer_path, trust_remote_code=True)

    # ── 读取 CSV ────────────────────────────────────────────────────
    print("📖 读取 CSV...")
    df = pd.read_csv(csv_path, low_memory=False)
    total_rows = len(df)
    print(f"  总行数: {total_rows:,}")

    if sample_frac is not None and sample_frac < 1.0:
        df = df.sample(frac=sample_frac, random_state=42).reset_index(drop=True)
        print(f"  采样 {sample_frac*100:.0f}%: {len(df):,} 行")

    # ── 提取 input 文本 ─────────────────────────────────────────────
    print("🔍 提取 messages 内容...")
    if "messages" in df.columns:
        input_texts = df["messages"].fillna("").apply(extract_text_from_messages).tolist()
    else:
        print("  ⚠️  无 messages 列，跳过 input token 统计")
        input_texts = None

    # ── 提取 output 文本 ─────────────────────────────────────────────
    if "old_response" in df.columns:
        output_texts = df["old_response"].fillna("").astype(str).tolist()
        # 字符长度（过滤空行）
        resp_lens = np.array([len(t) for t in output_texts if t.strip()])
    else:
        print("  ⚠️  无 old_response 列")
        output_texts = None
        resp_lens = None

    # ── tokenize input ───────────────────────────────────────────────
    if input_texts:
        print("🔢 统计 input token 数...")
        in_counts = np.array(batch_tokenize(tokenizer, input_texts))
        in_mask = in_counts > 0
        in_counts = in_counts[in_mask]
    else:
        in_counts = None

    # ── tokenize output ──────────────────────────────────────────────
    if output_texts:
        print("🔢 统计 output token 数...")
        out_texts_nonempty = [t for t in output_texts if t.strip()]
        out_counts = np.array(batch_tokenize(tokenizer, out_texts_nonempty))
        out_counts = out_counts[out_counts > 0]
    else:
        out_counts = None

    # ── 汇总打印 ──────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("📊 统计结果（可直接贴入 README）")
    print("=" * 60)

    sample_note = f"（采样 {sample_frac*100:.0f}%，约 {len(df):,} 条）" if sample_frac and sample_frac < 1.0 else f"（全量 {len(df):,} 条）"

    import os
    fname = os.path.basename(csv_path)

    print(f"""
## 输入输出分布{sample_note}

| 指标 | 数值 |
|------|------|""")

    if in_counts is not None and len(in_counts) > 0:
        ps = percentile_str(in_counts, [50, 90, 99])
        print(f"| input tokens (mean / p50 / p90 / p99 / max) | {fmt(in_counts.mean())} / {fmt(ps['p50'])} / {fmt(ps['p90'])} / {fmt(ps['p99'])} / {fmt(in_counts.max())} |")

    if out_counts is not None and len(out_counts) > 0:
        ps = percentile_str(out_counts, [50, 90, 99])
        print(f"| output tokens (mean / p50 / p90 / p99 / max) | {fmt(out_counts.mean())} / {fmt(ps['p50'])} / {fmt(ps['p90'])} / {fmt(ps['p99'])} / {fmt(out_counts.max())} |")

    if resp_lens is not None and len(resp_lens) > 0:
        ps = percentile_str(resp_lens, [50, 90])
        print(f"| old_response 字符长度 (mean / p50 / p90) | {fmt(resp_lens.mean())} / {fmt(ps['p50'])} / {fmt(ps['p90'])} |")

    print(f"| 统计样本 | 来源：`{fname}` |")
    print()

    # ── 返回 dict 供调用方使用 ────────────────────────────────────────
    result = {
        "sample_size": len(df),
        "total_rows": total_rows,
        "sample_frac": sample_frac,
        "csv_file": fname,
    }
    if in_counts is not None and len(in_counts) > 0:
        result["input_tokens"] = {
            "mean": float(in_counts.mean()),
            "p50": float(np.percentile(in_counts, 50)),
            "p90": float(np.percentile(in_counts, 90)),
            "p99": float(np.percentile(in_counts, 99)),
            "max": float(in_counts.max()),
        }
    if out_counts is not None and len(out_counts) > 0:
        result["output_tokens"] = {
            "mean": float(out_counts.mean()),
            "p50": float(np.percentile(out_counts, 50)),
            "p90": float(np.percentile(out_counts, 90)),
            "p99": float(np.percentile(out_counts, 99)),
            "max": float(out_counts.max()),
        }
    if resp_lens is not None and len(resp_lens) > 0:
        result["resp_char_len"] = {
            "mean": float(resp_lens.mean()),
            "p50": float(np.percentile(resp_lens, 50)),
            "p90": float(np.percentile(resp_lens, 90)),
        }
    return result


def main():
    parser = argparse.ArgumentParser(description="计算数据集 CSV 的 token 分布统计")
    parser.add_argument("--csv", required=True, help="输入 CSV 文件路径")
    parser.add_argument(
        "--tokenizer",
        default="/mnt/ai-infra/models/Qwen2.5-72B-Instruct",
        help="HuggingFace tokenizer 路径（默认 Qwen2.5-72B-Instruct）",
    )
    parser.add_argument(
        "--sample",
        type=float,
        default=None,
        help="采样比例（0~1），大文件可用 0.1 加速；默认全量",
    )
    args = parser.parse_args()
    compute_stats(args.csv, args.tokenizer, args.sample)


if __name__ == "__main__":
    main()
