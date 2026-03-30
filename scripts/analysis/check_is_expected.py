#!/usr/bin/env python3
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/src'))
from llm_benchmark.analysis.analysis.single_exp import load_exp_csv, analysis_row
import pandas as pd
import numpy as np

CSV = "/mnt/ai-infra/users/wnd/workspace/execute/guofan/logs/chart-deep-v5-2-8h20_replay_20260329_130526/chart-deep-v5-2-8h20_replay_100rpm.csv"
df, _ = load_exp_csv(CSV)
print("总行数:", len(df))

rows_info = []
for i, row in df.iterrows():
    try:
        info = analysis_row(row)
        if info["analysis_status"] != "data_ok":
            rows_info.append({"idx": i, "request_id": row["request_id"], "is_expected": None})
            continue

        tl = info["token_list"]
        tpots = []
        for j in range(2, len(tl) - 1):
            dt = tl[j]["timestamp"] - tl[j-1]["timestamp"]
            if dt > 0:
                tpots.append(dt)

        max_tpot = max(tpots) if tpots else 0
        ttfs = info["ttfs"]
        e2e = info["e2e"]

        if max_tpot > 10:
            is_exp = -2
        elif ttfs > 10:
            is_exp = -3
        elif e2e > 180:
            is_exp = -4
        else:
            is_exp = 1

        rows_info.append({
            "idx": i,
            "request_id": int(row["request_id"]),
            "income_time": str(row["income_time"]),
            "ttfs": round(ttfs, 3),
            "e2e": round(e2e, 2),
            "max_tpot": round(max_tpot, 3),
            "is_expected": is_exp
        })
    except Exception as ex:
        rows_info.append({"idx": i, "is_expected": None, "err": str(ex)[:50]})

df_info = pd.DataFrame(rows_info)

print("\n=== is_expected 分布 ===")
print(df_info["is_expected"].value_counts().to_string())

df_unexpected = df_info[df_info["is_expected"] != 1]
print("\n不符合预期总数:", len(df_unexpected))

reason_map = {-2: "max_tpot>10s", -3: "ttfs>10s", -4: "e2e>180s", -1: "status!=200"}
for code in [-2, -3, -4, -1]:
    sub = df_unexpected[df_unexpected["is_expected"] == code]
    if len(sub) > 0:
        print("\n  {}: {} 条".format(reason_map[code], len(sub)))
        for _, r in sub.head(10).iterrows():
            print("    request_id={}, income_time={}, max_tpot={}s, ttfs={}s, e2e={}s".format(
                r.get("request_id", "?"),
                r.get("income_time", "?"),
                r.get("max_tpot", 0),
                r.get("ttfs", 0),
                r.get("e2e", 0)
            ))

if "max_tpot" in df_info.columns:
    valid = df_info["max_tpot"].dropna()
    print("\n=== max_tpot 分布（全部 {} 条）===".format(len(valid)))
    print("  mean={}s, p50={}s, p90={}s, p99={}s, max={}s".format(
        round(valid.mean(), 3), round(valid.quantile(0.5), 3),
        round(valid.quantile(0.9), 3), round(valid.quantile(0.99), 3),
        round(valid.max(), 3)
    ))
    print("  >5s: {} 条, >10s: {} 条, >20s: {} 条".format(
        int((valid > 5).sum()), int((valid > 10).sum()), int((valid > 20).sum())
    ))
