---
name: qps-peak-finder-analysis
description: Use when qps-peak-finder three phases are complete and you need to synthesize results — merging Phase 2 + Phase 3 data, estimating server-side concurrency via Little's Law from Phase 1 CSV, generating capacity curve charts, and producing a REPORT.md with three operating-point anchors (extreme RPS / ideal RPS / production RPM).
---

# QPS Peak Finder Analysis

## Overview

`qps-peak-finder` 三阶段执行完成后的**结果汇总与报告生成**。

核心产出：
- Phase 2 + Phase 3 合并容量曲线（HTML 图表）
- 三锚点对照表：**极限 RPS（Phase 2 首档）/ 理想 RPS（Phase 2 收敛）/ 生产 RPM（可选，Phase 3 首档）**
- 极限承载并发估算（Little's Law，来自 Phase 1 峰值档，非客户端并发数）
- REPORT.md（模板 B 扩展版，含 peak-finder 专属三节）

> **极限 RPS 定义**：Phase 2 第一轮探测 RPS（主动设置为 Phase 1 max_rps_estimate × 1.2 附近的实测最高运行点）。服务此时 SLA 严重超标但仍在运行，**恒大于理想 RPS**。Phase 1 的 `max_rps_estimate` 是公式估算值（decode_throughput / avg_output_len），在高并发下失真，**不用作极限 RPS**。

**设计文档**：`clingo/docs/designs/2026-03-20-qps-peak-finder-analysis-design.md`

---

## 前置条件

- Phase 3 日志出现 "Phase 3 Complete"，所有档位 CSV 已生成
- Phase 1 各档目录含 `*.csv` 文件（非 `.argv.csv`）
- Phase 2 checkpoint.md 记录了 `ideal_rps` 和收敛 bracket
- 已知 `sla_config`（YAML 或模型 `.env` 中）

---

## Step 1 — Little's Law + 饱和指标提取

**档位**：Phase 1 **峰值档**（吞吐最高的那档，即翻倍前的最后一档；饱和确认档已过载，不代表正常运行状态）

```python
import pandas as pd, glob, os, json

def phase1_peak_metrics(phase1_peak_dir: str, max_rps_estimate: float,
                        decode_throughput: float) -> dict:
    """
    phase1_peak_dir : 峰值档目录，如 logs/.../con400/（吞吐最高档，翻倍前）
    max_rps_estimate: checkpoint 中该档的 max_rps_estimate（req/s）
    decode_throughput: checkpoint 中该档的 decode_throughput（tokens/s）
    """
    csv_files = [f for f in glob.glob(os.path.join(phase1_peak_dir, "*.csv"))
                 if not f.endswith(".argv.csv")]
    df = pd.read_csv(csv_files[0], low_memory=False)
    df_ok = df[df["status"] == 200].copy()

    def parse_metrics(tl_str):
        try:
            tl = json.loads(tl_str)
            start  = tl[0]["timestamp"]
            first  = next((t["timestamp"] for t in tl
                           if t.get("data", "") not in ("[START]", "[END]")), None)
            end    = tl[-1]["timestamp"]
            ttfs   = (first - start) if first is not None else None
            e2e    = end - start
            return ttfs, e2e
        except Exception:
            return None, None

    df_ok[["ttfs_s", "e2e_s"]] = df_ok["token_list"].apply(
        lambda x: pd.Series(parse_metrics(x)))
    df_ok = df_ok.dropna(subset=["ttfs_s", "e2e_s"])

    mean_e2e = df_ok["e2e_s"].mean()
    l_server = max_rps_estimate * mean_e2e   # Little's Law: L = λ × W

    success_rate = round(len(df_ok) / len(df) * 100, 1)

    return {
        "max_rps_estimate":         round(max_rps_estimate, 4),
        "decode_throughput":        decode_throughput,
        "success_rate":             success_rate,     # 峰值档成功率（通常 <60%；其余请求超时未计入延迟）
        "ttfs_p90_s":               round(df_ok["ttfs_s"].quantile(0.90), 3),
        "e2e_p90_s":                round(df_ok["e2e_s"].quantile(0.90), 2),
        "mean_e2e_s":               round(mean_e2e, 2),
        "server_concurrency":       round(l_server, 1),
    }
```

> **为什么用峰值档而非饱和确认档**：饱和确认档（吞吐翻倍后）已严重过载，其延迟数据是崩溃状态，不代表正常承载能力。峰值档是服务能达到的最高吞吐点，其 TTFS/E2E 展示的是"硬件上限时真实发生了什么"，更直观体现超出 SLA 的原因。  
> L = λ × W = max_rps_estimate（吞吐估算 req/s）× mean E2E（峰值档平均全链路延迟）

---

## Step 2 — 合并 Phase 2 + Phase 3 数据

Phase 2（`rpsX.XXXX/`）和 Phase 3（`qpsX.XXXX/`）均为 `--request-rate` 模式，格式完全兼容。

```bash
MODEL="xinghan-chart-32b-v1-1-agent"   # 按实际模型名替换
TP="8tp"
DATE=$(date +%Y%m%d)
MERGED="logs/${MODEL}-${TP}-phase23_merged_${DATE}"
mkdir -p "$MERGED"

# Phase 2 档位
for d in logs/${MODEL}-${TP}-phase2_*/rps*/; do
    [ -d "$d" ] && cp -rl "$d" "$MERGED/$(basename $d)"
done

# Phase 3 档位
for d in logs/${MODEL}-${TP}-phase3_*/qps*/; do
    [ -d "$d" ] && cp -rl "$d" "$MERGED/$(basename $d)"
done

echo "合并完成，共 $(ls $MERGED | wc -l) 个档位"
```

> ⚠️ 必须用 `cp -rl`（硬链接目录），**不能用 `ln -sfn`（符号链接到目录）**：`Path.glob("**/*.csv")` 默认不追踪指向目录的符号链接。

---

## Step 3 — 容量曲线图表

创建 YAML 配置后调用 `qps-sweep-comparison` Skill：

```yaml
# configs/models/<model>/<tp>_peak_finder_analysis.yaml
groups:
  - label: "<model> <TP>×1实例"
    dir: "logs/<model>-<tp>-phase23_merged_<date>"
  # 多部署对比时追加：
  # - label: "<model> <TP2>×1实例"
  #   dir: "logs/<model>-<tp2>-phase23_merged_<date>"

x_key: request_rate
output_dir: "results/<model>_peak_finder_<date>"

sla_config:
  ttfs_p90: 1.5         # 通用基准（s）
  e2e_p90: 150.0        # 通用基准（s）
  success_rate: 0.99
  # 模型特定时取消注释（如 tianji：E2E P95 ≤ 400ms）：
  # custom:
  #   - metric: e2e
  #     percentile: 95
  #     limit: 0.4
  #     label: "E2E P95"
```

```bash
cd /mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark

/mnt/ai-infra/users/wnd/workspace/execute/guofan/.venv/bin/python3 \
    -m llm_benchmark.analysis.analysis.multi_exp_compare \
    --config /mnt/ai-infra/users/wnd/workspace/execute/guofan/configs/models/<model>/<tp>_peak_finder_analysis.yaml
```

---

## Step 4 — 生成 REPORT.md

### 三锚点对照表（§0，peak-finder 专属）

锚点指标列从 `sla_config` 动态读取（不硬编码），通用基准为 TTFS P90 + E2E P90 + 成功率：

```markdown
## §0 Peak Finder 三锚点摘要

| 操作点 | RPS | 服务端承载并发 | TTFS P90 | E2E P90 | 成功率 |
|--------|-----|--------------|---------|---------|--------|
| 极限 RPS（Phase 1 饱和）| <extreme_rps> req/s | <server_concurrency>（L=λW）| 不适用 | 不适用 | — |
| 理想 RPS（Phase 2 收敛）| <ideal_rps> req/s | — | <ms> | <s> | <N>% |
| 生产 RPM（可选）| <prod_rps> req/s | — | <ms> | <s> | <N>% |

> 极限 RPS 下服务处于饱和区，延迟指标无 SLA 参考意义；承载并发 = max_rps_estimate × mean_E2E（Little's Law）。
```

> **生产 RPM 锚点数据来源**：Phase 3 第一档（production_rps 或最接近档位）的 CSV，用 `analysis_response()` 提取指标。

### REPORT.md 完整结构（模板 B 扩展）

```markdown
# <Model> QPS Peak Finder 报告

## §0 Peak Finder 三锚点摘要
[三锚点对照表，见上]

## §1 Phase 1 — 饱和探测摘要
[各档吞吐表，饱和确认档加粗]
峰值 decode_throughput = X tokens/s（Phase 1 峰值档 max_rps_estimate 仅供 Little's Law 参考，非极限 RPS）

## §2 Phase 2 — 自适应逼近过程
[各轮 RPS / SLA指标 / 判断 / bracket 表]
收敛：ideal_rps = X req/s，bracket [lo, hi] 宽 X%，共 N 档

## §3 Phase 3 — 上线验证网格（容量曲线）
[qps-sweep-comparison 输出的 SLA 分析表]
![plot_latency_2d](plot_latency_2d.html)

--- 以下沿用标准模板 B ---
## 测试背景
## SLA 基准
## 各档位明细
## 拐点分析
## 8TP vs 4TP 对比结论（若有）
## 上线建议
```

---

## Step 5 — 归档

```bash
# 1. model-context.md 追加（写入两个新字段）
extreme_rps: <x>
server_concurrency_at_extreme: <n>

# 2. results/README.md 新增实验条目（同 qps-sweep-comparison 规范）

# 3. results/models/INDEX.yaml 更新字段
# ─── 字段说明 ─────────────────────────────────────────────────────────
# sla_max_qps_rps / sla_max_qps_rpm : Phase 2 收敛的 ideal_rps（SLA 合规上限）
# saturation_rps / saturation_rpm   : Phase 2 首档实测 RPS（serve.py 仪表盘"极限 RPS"）
#                                     ⚠️ 不用 Phase 1 max_rps_estimate——高并发下公式估算失真
#                                       → Phase 2 首档是主动发压的实测值，恒大于 ideal_rps
# saturation_ttfs_p90_s             : Phase 2 首档 TTFS P90（serve.py 使用）
# saturation_e2e_p90_s              : Phase 2 首档 E2E P90（serve.py 使用）
# saturation_concurrency            : Little's Law 估算，来自 Phase 1 峰值档（整数，向下取整）
# saturation_decode_throughput      : Phase 1 峰值档 decode_throughput（tokens/s）
# linked_experiments                : 追加 results/<peak_finder_dir>
# ─────────────────────────────────────────────────────────────────────

performance:
  sla_max_qps_rps: <x>                       # ideal_rps，req/s
  sla_max_qps_rpm: <x>                       # ideal_rps × 60
  saturation_rps: <phase2_first_probe_rps>   # Phase 2 首档实测（serve.py 展示极限 RPS）
  saturation_rpm: <phase2_first_probe_rps × 60>
  saturation_concurrency: <int>              # Little's Law，来自 Phase 1 峰值档，取整
  saturation_decode_throughput: <x>          # Phase 1 峰值档 decode_throughput（tokens/s）
  saturation_ttfs_p90_s: <x.xxx>            # Phase 2 首档 TTFS P90（s）
  saturation_e2e_p90_s: <x.xx>              # Phase 2 首档 E2E P90（s）

linked_experiments:
  - results/<peak_finder_result_dir>       # 新增一行

# ─── 可选：多 TP 对比时 ────────────────────────────────────────────────
# 若同时测了 8TP 与 4TP，则在各自子节填写，并添加：
# tp8_vs_tp4_ratio: <8TP_ideal_rps / 4TP_ideal_rps>
```

---

## 常见问题

| 问题 | 原因 | 处理 |
|------|------|------|
| Phase 2 和 Phase 3 子目录命名不同（rps vs qps）| 历史命名差异 | `multi_exp_compare` 按 CSV 中的 `request_rate` 字段绘图，目录名不影响结果 |
| Little's Law 结果远大于客户端并发数 | 饱和档 E2E 极长（数百秒）| 属正常现象，服务严重过载，大量请求在 running queue 排队 |
| Phase 3 某档 SLA FAIL | ideal_rps 可能高估 | 回查 Phase 2 bracket，检查是否有 next_rps 计算错位 bug |
| 生产 RPM 锚点数据缺失 | production_rps 未知 / Phase 3 未从 prod_rps 起跑 | 用 Phase 3 最低档数据替代，备注"估算" |

---

## 示例：chart-32b 8TP（2026-03-19）

```
Phase 1 饱和确认档：con400，max_rps_estimate = 7.37 req/s
Little's Law：mean_e2e ≈ X s → server_concurrency ≈ Y
Phase 2 收敛：ideal_rps = 7.6132 req/s，bracket [7.6132, 7.8058]，宽 2.5%
Phase 3 档位：0.667 / 2.982 / 5.298 / 7.613 req/s（全部 SLA ✅）
合并后数据点：11档（7档 Phase 2 + 4档 Phase 3）
```
