#!/usr/bin/env python3
"""
合并 ziwei_4tp_qps_20260310 三批历史结果到统一目录

来源：
  logs/ziwei_4tp_qps_20260310_150343  → 平铺，QPS: 0.84, 0.83, 0.82, 0.80, 0.50
  logs/ziwei_4tp_qps_20260310_182639  → 平铺，QPS: 0.49, 0.48, 0.47
  logs/ziwei_4tp_qps_20260310_201049  → qps_X.XX/ 子目录，QPS: 1.00→0.46 共16档

目标：
  logs/ziwei_4tp_qps_20260310_all/qps_X.XX/vanilla_qpsX.XX.csv
                                            vanilla_qpsX.XX.argv.csv
  合计 24 档（复制，不移动，保留原目录）
"""

import shutil
import re
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[2]
LOGS_DIR = PROJECT_DIR / "logs"

SRC_FLAT = [
    LOGS_DIR / "ziwei_4tp_qps_20260310_150343",
    LOGS_DIR / "ziwei_4tp_qps_20260310_182639",
]
SRC_SUBDIR = LOGS_DIR / "ziwei_4tp_qps_20260310_201049"
DEST = LOGS_DIR / "ziwei_4tp_qps_20260310_all"

copied = []
skipped = []
errors = []

print("=" * 60)
print("4TP QPS 历史结果合并")
print("=" * 60)
print(f"  目标目录: {DEST}")
print()

DEST.mkdir(exist_ok=True)

# ── 处理平铺目录（150343 / 182639）──────────────────────────
for src_dir in SRC_FLAT:
    print(f"[平铺] {src_dir.name}")
    csv_files = [f for f in src_dir.glob("vanilla_qps*.csv")
                 if not f.name.endswith(".argv.csv")]
    for csv_file in sorted(csv_files):
        # 从文件名提取 QPS，例如 vanilla_qps0.84.csv → 0.84
        m = re.search(r"vanilla_qps([\d.]+)\.csv$", csv_file.name)
        if not m:
            skipped.append(str(csv_file))
            continue
        qps_str = m.group(1)
        qps_float = float(qps_str)
        qps_tag = f"{qps_float:.2f}"  # 统一两位小数
        subdir = DEST / f"qps_{qps_tag}"
        subdir.mkdir(exist_ok=True)

        # 复制主 CSV 和 argv CSV
        for suffix in ["", ".argv"]:
            src = src_dir / f"vanilla_qps{qps_str}{suffix}.csv"
            if src.exists():
                dst = subdir / f"vanilla_qps{qps_tag}{suffix}.csv"
                shutil.copy2(src, dst)
                copied.append(f"  qps_{qps_tag}/{dst.name}  ← {src_dir.name}")
            else:
                skipped.append(str(src))

# ── 处理子目录来源（201049）──────────────────────────────────
print(f"[子目录] {SRC_SUBDIR.name}")
for qps_dir in sorted(SRC_SUBDIR.glob("qps_*")):
    if not qps_dir.is_dir():
        continue
    qps_tag = qps_dir.name.replace("qps_", "")
    try:
        qps_float = float(qps_tag)
        qps_tag = f"{qps_float:.2f}"
    except ValueError:
        skipped.append(str(qps_dir))
        continue

    dest_subdir = DEST / f"qps_{qps_tag}"
    dest_subdir.mkdir(exist_ok=True)

    for csv_file in qps_dir.glob("vanilla_qps*.csv"):
        dst = dest_subdir / csv_file.name
        shutil.copy2(csv_file, dst)
        copied.append(f"  qps_{qps_tag}/{csv_file.name}  ← {SRC_SUBDIR.name}")

# ── 汇总 ─────────────────────────────────────────────────────
all_qdirs = sorted(DEST.glob("qps_*"))
print()
print(f"合并完成：{len(all_qdirs)} 个 QPS 档位")
print()
print(f"{'QPS 档位':<12} {'CSV 数':>6}  来源")
print("-" * 50)
for qd in all_qdirs:
    csvs = list(qd.glob("*.csv"))
    # 推断来源
    qps_v = float(qd.name.replace("qps_", ""))
    if qps_v in [0.84, 0.83, 0.82, 0.80, 0.50]:
        src_tag = "150343"
    elif qps_v in [0.49, 0.48, 0.47]:
        src_tag = "182639"
    else:
        src_tag = "201049"
    print(f"  {qd.name:<12} {len(csvs):>4} 个   ← {src_tag}")

print()
print(f"全部 QPS 档位：")
qps_values = sorted([float(qd.name.replace("qps_", "")) for qd in all_qdirs])
print("  " + "  ".join(f"{v:.2f}" for v in qps_values))

if skipped:
    print()
    print(f"⚠️  跳过 {len(skipped)} 个（文件不存在或格式不匹配）：")
    for s in skipped:
        print(f"   {s}")

print()
print(f"目标目录: {DEST}")
