---
name: qps-peak-finder
description: Use when onboarding a new LLM model with unknown QPS capacity — finding hardware-limit RPS via saturation test, then adaptively probing for ideal SLA-compliant RPS, and finally running a production-anchored 4-point grid validation. Use instead of qps-benchmark-sweep when the inflection point is completely unknown.
---

# QPS Peak Finder

## Overview

「先顶峰、后摸底」——用最少档位获得两个关键锚点：
- **极限 RPS**：当前硬件部署下的绝对吞吐上限
- **理想 RPS**：满足 SLA 约束的最大可持续 RPS

**三阶段流程**：饱和探测 → 自适应逼近 → 上线验证网格

**设计文档**：`clingo/docs/designs/2026-03-18-qps-peak-finder-design.md`

---

## 前置条件

- 模型已部署，服务 URL 可访问，已完成健康检查
- 数据集已准备（含 `income_time`, `messages`, `prompt` 列）
- **`old_response` 列必须有效填充**（DataConverter 默认不提取模型回复，需在步骤1.5 手动回填；详见 `traffic-dataset-prep` Skill 验证 Checklist 及对应模型的 `clingo/docs/ai_data/` 文档）
- Python venv：`/mnt/ai-infra/users/wnd/workspace/execute/guofan/.venv/bin/python3`
- `BENCHMARK_SCRIPT`：`${BENCH_ROOT}/modao/src/scripts/example_llm_benchmark_test.sh`
- 已知或可估算 `production_rps`（上线 Grafana RPM ÷ 60）

---

## Phase 0：数据集预分析

在启动压测前运行一次，获取输出 token 分布，用于估算 `max_rps_estimate`。

```bash
.venv/bin/python3 scripts/analysis/analyze_peak_finder.py \
    --phase 0 \
    --dataset datas/output_guoxue/<MODEL>_2026-MM-DD.csv \
    --tokenizer /path/to/tokenizer
```

产出：
- `avg_output_len`（tokens）← 换算 max_rps_estimate 的分母
- P50/P90/P99 输出长度分布（作为参考）

> **依赖**：数据集 `old_response` 列必须非空（见前置条件）。
> 若 `old_response` 全为空，Phase 0 会报 `KeyError`；先按 `traffic-dataset-prep` SKILL 步骤1.5 修复数据集。
>
> **模型参考文档**：每个模型的数据链路细节、`old_response` 回填方法及 Phase 0 输出示例见 `clingo/docs/ai_data/<model>-data-structure.md`。

---

## Phase 1：饱和探测

**模式**：`--max-concurrency`（不限速，固定并发窗口）  
**目标**：找到 `peak_decode_throughput`，换算 `max_rps_estimate`

### 执行前：先验并发信息收集（可选加速）

在启动 Phase 1 之前，**询问操作人员**：

> "模型是否已上线？若是，请提供 Grafana 上的 max active_requests 峰值（并发数）。  
> 有此数据可跳过低档位爬坡，节省约 15~25 分钟。  
> 若模型未上线或无数据，直接回复"无"，将从默认 con=5 开始。"

- 若操作人员提供了数值 N → 设置 `INIT_CONCURRENCY=N`，从 `con=N` 起跳
- 若回复"无"或未提供 → `INIT_CONCURRENCY` 不设，从 `con=5` 走完整流程

> **第一档无基准时的处理**：当设置了 `INIT_CONCURRENCY` 时，`con=N` 作为翻倍起点（等效于认为更低并发已充分测试），直接运行 `con=N`，再运行 `con=N×2`，以这两档的吞吐增幅启动正常饱和判断规则。  
> 若 `con=N` 与 `con=N×2` 的增幅 <1%，说明生产并发已在饱和区，直接确认 `peak_throughput`。

### 执行

每档固定时长 **300s（5min）**，用 `--request-time-limit` 控制，每档独立运行后读取结果再决定下一档并发数。

```bash
OUTPUT_DIR="logs/${MODEL}_phase1_saturation_$(date +%Y%m%d)"
CONCURRENCY=${INIT_CONCURRENCY:-5}   # 有先验并发数时从此起跳（省去低档位爬坡）；否则默认 5

LEVEL_DIR="${OUTPUT_DIR}/con${CONCURRENCY}"
mkdir -p "${LEVEL_DIR}"

TARGET_MODEL="${TARGET_MODEL}" \
TOKENIZER="${TOKENIZER}" \
DATASET_PATH="${DATASET_PATH}" \
OUTPUT_DIR="${LEVEL_DIR}" \
bash "${BENCHMARK_SCRIPT}" \
    --skip-launch-server \
    --server-url "${SERVER_URL}" \
    --max-concurrency "${CONCURRENCY}" \
    --num-requests $((CONCURRENCY * 200)) \
    --request-time-limit 300 \
    --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
    --no-kvcache \
    || echo "⚠️ con=${CONCURRENCY} 异常，继续"
# → 读取结果 → 对照饱和判断规则 → 决定下一档 CONCURRENCY
```

### 每档指标提取

```python
import pandas as pd

def calc_phase1_metrics(csv_path):
    df = pd.read_csv(csv_path)
    df_ok = df[df["status"] == 200].copy()
    df_ok["start_time"] = pd.to_datetime(df_ok["start_time"])
    df_ok["end_time"]   = pd.to_datetime(df_ok["end_time"])
    total_dur = (df_ok["end_time"].max() - df_ok["start_time"].min()).total_seconds()
    decode_throughput = df_ok["completion_token_cnt"].sum() / total_dur
    avg_output_len    = df_ok["completion_token_cnt"].mean()
    max_rps_estimate  = decode_throughput / avg_output_len
    return {
        "decode_throughput": round(decode_throughput, 2),
        "avg_output_len":    round(avg_output_len, 1),
        "max_rps_estimate":  round(max_rps_estimate, 3),
    }
```

### 饱和判断规则（两段式步进）

| 相邻两档吞吐增幅 | 结论 | 下一档并发 |
|----------------|------|-----------|
| **> 10%** | 未饱和 | `current × 2`（翻倍快速逼近） |
| **1%~10%** | 接近饱和 | `current + 10`（线性小步精查） |
| **< 1%** | ✅ 已饱和 | 停止，记录 `peak_throughput` |

> **为什么要两段式**：纯翻倍（5→10→20→40→80）步进太粗，会跳过真实饱和点（如最优并发为 60，测完 40 直接跳 80 会漏掉）。进入接近饱和区后改为 +10 线性步进，精确捕获饱和拐点。
>
> **典型轨迹示例**（最优并发 ≈ 60）：
> `5 → 10 → 20 → 40`（增幅 >10%，翻倍）`→ 50 → 60 → 70`（增幅进入 1~10%，+10）`→ 发现 60→70 增幅 <1%，饱和确认`

### Phase 1 检查点（写入 `phase1_checkpoint.md`）

```
peak_decode_throughput  = XX tokens/s
avg_output_len          = XX tokens
max_rps_estimate        = XX req/s
max_running_concurrency = XX
Phase 2 起始 QPS        = max_rps_estimate × 1.2 = XX req/s
```

---

## Phase 2：自适应逼近

**模式**：`--request-rate`（定速发压）  
**每档时长**：1200s（20min）  
**起始 QPS**：`max_rps_estimate × 1.2`  
**初始步长**：`max_rps_estimate × 10%`

### 执行（单档模板）

```bash
PROBE_QPS=<本档值>
LEVEL_DIR="${OUTPUT_DIR}/phase2_rps${PROBE_QPS}"
mkdir -p "${LEVEL_DIR}"
NUM_PROMPTS=$(echo "$PROBE_QPS * 1200" | bc | awk '{print int($1)+1}')

TARGET_MODEL="${TARGET_MODEL}" \
TOKENIZER="${TOKENIZER}" \
CONFIG_LIST="${PROBE_QPS},0,0,0" \
DATASET_PATH="${DATASET_PATH}" \
NUM_PROMPTS="${NUM_PROMPTS}" \
OUTPUT_DIR="${LEVEL_DIR}" \
bash "${BENCHMARK_SCRIPT}" \
    --skip-launch-server \
    --server-url "${SERVER_URL}" \
    --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
    || echo "⚠️ rps=${PROBE_QPS} 异常，记录后继续"

sleep ${COOLDOWN_SECS:-60}
```

### SLA 基准

| 指标 | 通用基准 | 说明 |
|------|---------|------|
| TTFS P90 | ≤ 1500 ms | 首句延迟 |
| E2E P90 | ≤ 150 s | 完整响应上限 |
| 模型特定 | 见下方注释 | 如 tianji: E2E P95 ≤ 400ms |

### 两阶段决策（Phase 2a）

**阶段 1：比例快速逼近**（无 bracket 时，`run_phase2_auto.sh` 启动初期）

| 情况 | 下一档 QPS |
|------|-----------|
| 首档 + 超载（current > peak_rps） | `peak_rps × 0.8` |
| SLA ❌，超标 X% | `current × (1/worst_ratio)^0.8` |
| SLA ✅，裕量 > 20% | `current × min((1/worst_ratio)^0.6, 1.25)` |
| SLA ✅，裕量 5~20% | `current × (1/worst_ratio)^0.6` |
| SLA ✅，裕量 < 5% | 收敛，可传入已知 bracket 触发精查 |

**阶段 2：bracket 几何中点精查**（同时有 pass 记录 `lo` 和 fail 记录 `hi` 后自动启用）

| 条件 | 下一档 QPS |
|------|-----------|
| bracket 宽度 `(hi−lo)/lo` ≥ 3% | `sqrt(lo × hi)`（几何中点，每步宽度减半） |
| bracket 宽度 < 3% | ✅ 收敛，`ideal_rps = lo` |

> **bracket 维护规则**：`lo` = 历史最高通过 RPS；`hi` = 历史最低失败 RPS。  
> `run_phase2_auto.sh` 自动追踪并更新 `LO_RPS`/`HI_RPS`；支持通过 `INIT_LO`/`INIT_HI` 环境变量从中断点续跑。  
>
> **⚠️ 实现陷阱：next_rps 必须在 bracket 更新后重新计算**  
> `analyze_phase2` 在被调用时接收的是**调用时刻的旧 bracket**，它基于旧 `[lo, hi]` 算出 `next_rps` 并打印 `[NEXT_RPS=X]`。  
> shell 自动循环随后解析 `[SLA_PASS/FAIL]` 更新 `LO_RPS/HI_RPS`——但若直接提取 analyze 已打印的 `[NEXT_RPS]`，得到的是**旧 bracket 的几何中点**，不是更新后 bracket 的几何中点。  
> 典型症状：某档 Pass 后 LO 应上移，但下一档 RPS 反而比刚通过的档位低（例如 7.242 Pass → 下一档却探 7.221）。  
>
> **正确写法**：shell 循环在 LO/HI 更新后，用 shell/python 重新计算几何中点，**不复用** analyze 输出的 `[NEXT_RPS]`：
> ```bash
> # 更新 LO/HI 之后
> NEXT_RPS=$(python3 -c "import math; print(f'{math.sqrt(float(\"${LO_RPS}\")*float(\"${HI_RPS}\")):.4f}')")
> # 同时判断收敛
> CONVERGED=$(python3 -c "print('yes' if (float('${HI_RPS}')-float('${LO_RPS}'))/float('${LO_RPS}') < 0.03 else 'no')")
> ```
> 仅当 bracket 尚未建立（lo 或 hi 为空）时，才 fallback 读取 analyze 的 `[NEXT_RPS]`。
>
> **效果对比**（guoxue-72b 实测）：  
> 纯比例步进耗 11 次探测仍在振荡；bracket 模式已有 lo=0.2494、hi=0.2529（宽 1.4%），**1 次**即确认收敛。  
>
> **QPS 已低于 production_rps 托底**：`ideal_rps = production_rps`，结束。

### 人工检查点格式（每档写入 `phase2_checkpoint.md`）

```markdown
## Phase 2 检查点 — RPS=X.XX（第 N 档）

| 指标 | 本档 | 上档 | 变化 |
|------|------|------|------|
| decode_throughput | XX tokens/s | XX | +X% |
| max_active_requests | XX | XX | ±X |
| TTFS P90 | XXX ms | XXX ms | ▲/▼ |
| E2E P90 | XX s | XX s | ▲/▼ |
| SLA 状态 | ✅/❌ | — | — |

当前判断：[未达极限 / 接近极限 / 极限已锚定 / 理想RPS已锚定]
建议下一档 QPS：X.XX
如有调整意见请在此回复 ↓
```

---

## Phase 3：上线验证网格

**目的**：不是再次寻找 SLA 边界，而是在 `[production_rps, ideal_rps]` 区间内均匀补充 4 档稳定数据，  
供 `qps-sweep-comparison` Skill 绘制连续的延迟曲线（TTFS P90 / E2E P90 随 QPS 变化趋势）。  
4 档均应 SLA ✅；若有档位失败则说明 Phase 2 的 `ideal_rps` 被高估，需回检。

> **与 qps-sweep-comparison 的衔接**：Phase 3 输出目录直接传给 `qps-sweep-comparison` Skill，
> 可与 Phase 2 各档位结果合并绘图，覆盖从生产负载到极限边界的完整曲线。

**前提**：已知 `production_rps`（上线 Grafana RPM ÷ 60）和 `ideal_rps`（Phase 2 输出）  
**档位**：`np.linspace(production_rps, ideal_rps, 4)`  
**每档时长**：2700s（45min，比 Phase 2 长，提供更稳定的曲线样本）  
**档位间冷却**：60~90s

```bash
OUTPUT_DIR="logs/${MODEL}_phase3_grid_$(date +%Y%m%d)"

for QPS in ${LEVEL_1} ${LEVEL_2} ${LEVEL_3} ${LEVEL_4}; do
    LEVEL_DIR="${OUTPUT_DIR}/qps_${QPS}"
    mkdir -p "${LEVEL_DIR}"
    NUM_PROMPTS=$(echo "$QPS * 2700" | bc | awk '{print int($1)+1}')

    TARGET_MODEL="${TARGET_MODEL}" \
    TOKENIZER="${TOKENIZER}" \
    CONFIG_LIST="${QPS},0,0,0" \
    DATASET_PATH="${DATASET_PATH}" \
    NUM_PROMPTS="${NUM_PROMPTS}" \
    OUTPUT_DIR="${LEVEL_DIR}" \
    bash "${BENCHMARK_SCRIPT}" \
        --skip-launch-server \
        --server-url "${SERVER_URL}" \
        --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
        || echo "⚠️ QPS=${QPS} 异常，记录后继续"

    sleep ${COOLDOWN_SECS:-60}
done
```

Phase 3 完成后，先用 `analyze_peak_finder.py --phase 3` 快速汇总 SLA 合规状态，再将 `OUTPUT_DIR` 交给 **`qps-sweep-comparison` Skill** 生成图表和 REPORT.md：

```bash
# Phase 3 汇总分析（token_list 反推，无需额外字段）
.venv/bin/python3 scripts/analysis/analyze_peak_finder.py \
    --phase 3 \
    --dir "${OUTPUT_DIR}" \
    --ttfs-p90-limit 1.5 \
    --e2e-p90-limit 150.0
```

---

## 整体产出汇总

| 产出 | 来源 |
|------|------|
| `peak_decode_throughput` | Phase 1 |
| `max_running_concurrency` | Phase 1 |
| `extreme_rps`（极限 RPS） | Phase 2 |
| `ideal_rps`（理想 RPS） | Phase 2 |
| SLA 曲线图表 + REPORT.md | Phase 3 → qps-sweep-comparison |

---

## 常见问题

| 问题 | 原因 | 处理 |
|------|------|------|
| Phase 1 吞吐一直线性增长 | 数据集太小，`num_requests` 先耗尽 | 增大 `num_requests` 或换更大数据集 |
| Phase 2 从高 QPS 开始成功率就很低 | `max_rps_estimate` 高估 | 降低起始 QPS 到 `max_rps_estimate × 0.8` |
| Phase 2 找不到 SLA 超标点 | 模型性能很好，SLA 从未触发 | 继续向上探直到 `extreme_rps`，`ideal_rps = extreme_rps` |
| production_rps 未知 | 没有上线 Grafana 数据 | Phase 3 起始点改为 `ideal_rps × 0.5` |
| Phase 2 bracket Pass 后下一档 RPS 反而更低 | auto 脚本复用了 analyze 用旧 bracket 预算的 `[NEXT_RPS]`，LO 已更新但 next_rps 未重算 | bracket 更新后在 shell 层重新计算几何中点（见上方⚠️陷阱），不复用 analyze 打印值 |
