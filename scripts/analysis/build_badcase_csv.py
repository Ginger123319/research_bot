#!/usr/bin/env python3
"""
从原始 benchmark CSV 中抽取空响应行，合并为一个可被 analysis 工具加载的单一 CSV。

输出的 CSV 与原始 benchmark 格式完全一致，额外多一列 `qps_level` 供过滤使用。
放入 logs/chart-32b-8tp-null-decode/ 后可直接用 analysis 工具打开该目录。

用法：
  python3 scripts/analysis/build_badcase_csv.py \
      --log-dir  logs/chart-32b-8tp/qps_20260318_134151 \
      --out-csv  logs/chart-32b-8tp-null-decode/badcase_for_analysis.csv
"""

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

_PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_PROJECT / "third_party/speculative-decoding-benchmark"
                        "/3rdparty/llm-benchmark/src"))


def find_result_csv(qps_dir: Path) -> Path | None:
    candidates = [
        p for p in qps_dir.glob("*.csv")
        if not p.name.startswith("dataset") and not p.name.endswith(".argv.csv")
    ]
    return sorted(candidates)[-1] if candidates else None


def extract_qps_level(qps_dir: Path) -> float:
    try:
        return float(qps_dir.name.replace("qps_", ""))
    except ValueError:
        return 0.0


def is_empty_response(row: pd.Series) -> bool:
    """判定一行是否为空响应：status=200 且 token_list 仅有 [START]+[DONE]。"""
    if row.get("status") != 200:
        return False
    tl_raw = row.get("token_list", "")
    try:
        tl = json.loads(tl_raw) if isinstance(tl_raw, str) else tl_raw
        return isinstance(tl, list) and len(tl) == 2
    except Exception:
        return False


def run(log_dir: Path, out_csv: Path):
    qps_dirs = sorted(
        [d for d in log_dir.iterdir() if d.is_dir() and d.name.startswith("qps_")],
        key=lambda d: extract_qps_level(d)
    )

    frames = []
    for qps_dir in qps_dirs:
        qps_level = extract_qps_level(qps_dir)
        csv_path = find_result_csv(qps_dir)
        if csv_path is None:
            continue

        print(f"  [扫描] {qps_dir.name} ← {csv_path.name}")
        # 直接用 pandas 读取原始字符串，保留所有列的原始格式
        df = pd.read_csv(csv_path, encoding="utf-8-sig", dtype=str)
        # status 转为 int 用于过滤
        df["status"] = pd.to_numeric(df["status"], errors="coerce")

        empty_mask = df.apply(is_empty_response, axis=1)
        df_empty = df[empty_mask].copy()

        if df_empty.empty:
            continue

        df_empty.insert(0, "qps_level", str(qps_level))
        frames.append(df_empty)
        print(f"    → 提取 {len(df_empty)} 条空响应")

    if not frames:
        print("❌ 未找到任何空响应行")
        return

    df_all = pd.concat(frames, ignore_index=True)

    # 恢复 status 为整数字符串
    df_all["status"] = df_all["status"].astype(int).astype(str)

    out_csv.parent.mkdir(parents=True, exist_ok=True)
    df_all.to_csv(out_csv, index=False, encoding="utf-8-sig")

    print(f"\n✅ 合并完成：{len(df_all)} 条空响应")
    print(f"   输出：{out_csv}")
    print(f"   列名：{list(df_all.columns)}")
    print(f"\n启动分析工具：")
    print(f"   analysis --exp {out_csv.parent} --host 0.0.0.0 --port 18555")
    print(f"\n或在工具页面手动加载：")
    print(f"   {out_csv}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log-dir", default="logs/chart-32b-8tp/qps_20260318_134151")
    parser.add_argument("--out-csv", default="logs/chart-32b-8tp-null-decode/badcase_for_analysis.csv")
    args = parser.parse_args()
    run(Path(args.log_dir), Path(args.out_csv))


if __name__ == "__main__":
    main()
