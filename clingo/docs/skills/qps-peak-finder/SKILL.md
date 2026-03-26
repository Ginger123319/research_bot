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
- `avg_output_len`（tokens）← **换算 max_rps_estimate 的唯一权威分母**，也是 DURATION / COOLDOWN 自动推算的输入
- P50/P90/P99 输出长度分布（作为参考）

> **依赖**：数据集 `old_response` 列必须非空（见前置条件）。
> 若 `old_response` 全为空，Phase 0 会报 `KeyError`；先按 `traffic-dataset-prep` SKILL 步骤1.5 修复数据集。
>
> **模型参考文档**：每个模型的数据链路细节、`old_response` 回填方法及 Phase 0 输出示例见 `clingo/docs/ai_data/<model>-data-structure.md`。
>
> **Phase 0 vs Phase 1 avg_output_len：选用规则（两步判断）**
>
> **Step 1：Phase 0 数据质量检查（必做）**
>
> Phase 0 的可信度完全取决于 `old_response` 的质量。在使用 Phase 0 值之前，必须确认：
>
> | 检查项 | 合格标准 | 若不合格 |
> |--------|---------|---------|
> | `old_response` 来源 | 与**当前**模型版本行为一致（含推理链、输出格式相符）| 数据质量有缺陷，不可信 |
> | `old_response` 含 `<think>` 比例 | 若当前模型是推理模型，≥ 70%（否则缺少推理链）| 数据质量有缺陷 |
> | `old_response` 含 `<con>` 残留比例 | 应 ≈ 0%（当前推理模型不再输出 `<con>`）| 数据质量有缺陷 |
>
> 若 `old_response` 有已知结构性缺陷（如 `ai_deep_content` 未前置、模型版本升级后格式已变），
> Phase 0 值**不可信**，直接跳至 Step 2。
>
> **Step 2：选用哪个值**
>
> | 场景 | 使用哪个值 | 说明 |
> |------|-----------|------|
> | Phase 0 质量检查通过，Phase 1 偏差 ≤ 20% | Phase 0 权威值 | 样本量充足、无截断偏差 |
> | Phase 0 质量检查通过，Phase 1 偏差 > 20% | Phase 0 权威值，**但必须调查根因** | 偏差 >20% 是模型行为变化信号；若确认是模型升级导致，更新数据集后重新 Phase 0 |
> | **Phase 0 数据有已知结构性缺陷** | **Phase 1 实测值** | Phase 0 不可信时，Phase 1 实测是唯一可用参考；虽存在截断偏差，仍优于错误的 Phase 0 |
>
> **Phase 1 截断偏差的说明**（Phase 0 正常时 Phase 1 不应作为主值的原因）：
>
> Phase 1 饱和档窗口较短（300s~1h），在高并发饱和状态下，**未能在窗口内完成的长请求被丢弃**，
> 导致实测 `completion_token_cnt` 均值系统性偏低；低并发档样本量也常常不足。
> Phase 0 对全量 `old_response`（通常数千条）离线 tokenize，样本量充足、无截断偏差。
>
> **⚠️ 实战案例（guoxue-72b EAGLE3 4×H20）**：
> Phase 0 值 = 1386 tokens（`old_response` 未含 `ai_deep_content` 推理链，缺陷数据）；
> Phase 1 实测 = 2204 tokens；偏差 +59%。
> 正确做法：确认 Phase 0 数据有缺陷 → 使用 Phase 1 实测值 2204 tokens 计算 max_rps_estimate。
> 误用 Phase 0 值导致 Phase 2 START_RPS 高估 59%，引发灾难性过载（success rate 仅 11%）。

---

## Phase 0 产出：三阶段参数自动推算

> **使用时机**：用户未明确指定固定时长时，使用下面公式统一计算 Phase 1 / Phase 2 / Phase 3 参数。若用户已明确指定（如"每档跑 1 小时"），则按指定值执行，不使用公式。

```python
# Phase 0 产出的 avg_output_len（tokens）
avg_output_len = <Phase 0 输出>

# ── 三阶段统一公式 ────────────────────────────────────────────────
# 每档测试时长：系统稳态建立时间 + 足够观测窗口
#   原理：并发 N 个槽跑满需 N × avg_E2E ≈ avg_output_len × 2.5s，
#         稳态后再观测同等时长才能消除启动 bias
DURATION_SECS = max(300, int(avg_output_len * 2.5))
# 示例: avg=1386 → 3465s ≈ 1h；avg=500 → 1250s；avg=200 → 500s；avg=100 → 300s（下限）

# 档位间冷却：确保上一档全部在途请求排空，杜绝测试污染
#   原理：需等待最长 E2E 请求全部完成，保守取 avg_output_len / 2 秒
COOLDOWN_SECS = max(60, int(avg_output_len / 2))
# 示例: avg=1386 → 693s ≈ 12min；avg=300 → 150s；avg=100 → 60s（下限）
```

> **Phase 1 和 Phase 2/3 使用同一套公式**，唯一差别是 Phase 1 的下限更低（300s，因为低并发档位稳态建立快），Phase 2/3 下限为 1200s（需要更多样本计算 P90）。
>
> 实际使用：
> - Phase 1 `--request-time-limit` = `DURATION_SECS`（同上公式，下限 300s）
> - Phase 1 档位间 `sleep` = `COOLDOWN_SECS`（同上公式）
> - Phase 2/3 每档时长 = `max(1200, DURATION_SECS)`（下限提升到 1200s）
> - Phase 2/3 档位间 `sleep` = `COOLDOWN_SECS`（同上）

> **⚠️ 测试污染警告（长输出推理模型）**：
>
> 当模型的 E2E 延迟较长（P90 > 60s）时，时长和冷却不足会在 **所有三个阶段** 产生问题：
>
> | 阶段 | 症状 | 根因 |
> |------|------|------|
> | Phase 1 | 相邻档位 decode_throughput 剧烈振荡（如 363→213→413→105）| 300s 窗口太短，完成请求数 <50 条，采样噪声极大；且无档位间冷却，前轮在途请求污染后轮测量时间窗 |
> | Phase 2 | 低 RPS 档反而比高 RPS 档延迟更高（"倒挂"）；bracket HI 单调递减，不收敛 | 冷却不足导致前档在途请求积压到下档测试窗口 |
> | Phase 3 | 网格中低档位也出现 SLA ❌，曲线无规律 | 同 Phase 2 |
>
> **诊断**：Phase 1 振荡时检查各档 `max_active_requests`——若高并发档（如 con=80）实测活跃并发仍只有 30，说明服务器实际容量早已饱和，300s 窗口内能完成的请求数不足，数据不可信。
>
> **应对**：所有阶段重新按公式设置 `DURATION_SECS` 和 `COOLDOWN_SECS` 后重跑。

| `avg_output_len` 范围 | 模型类型参考 | DURATION_SECS | COOLDOWN_SECS |
|----------------------|------------|--------------|--------------|
| < 120 tokens | 分类器 / 安全过滤 | 300s（下限） | 60s（下限）|
| 200~500 tokens | 普通对话 | 500~1250s | 100~250s |
| 500~1500 tokens | 中等推理 | 1250~3750s | 250~750s |
| > 1500 tokens | 深度推理（如 guoxue-72b）| ≥ 3750s（建议取 3600s）| ≥ 750s（建议取 900s）|

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

每档时长由 Phase 0 自动推算（`max(300, int(avg_output_len × 2.5))`s），用户未指定时使用此公式；档位之间必须 sleep `COOLDOWN_SECS`，避免前档在途请求污染后档测量时间窗。

```bash
# MODEL_NAME = 算法提供的完整模型名（如 xinghan-guoxue-72b-v1-2-reason），作为 logs/ 第一层子目录
# MODEL      = 实验命名用短名（如 guoxue-v2、chart-32b-agent）
OUTPUT_DIR="logs/${MODEL_NAME}/${MODEL}_phase1_saturation_$(date +%Y%m%d)"
CONCURRENCY=${INIT_CONCURRENCY:-5}   # 有先验并发数时从此起跳（省去低档位爬坡）；否则默认 5

# PHASE1_TIME_LIMIT 和 COOLDOWN_SECS 由 Phase 0 自动推算（或用户指定）
# 短输出模型（avg<120 tokens）可用 300s；长输出推理模型（avg>1000 tokens）建议 3600s
# PHASE1_TIME_LIMIT=${PHASE1_TIME_LIMIT:-300}   # 未指定时默认 300，适合短输出模型
# COOLDOWN_SECS=${COOLDOWN_SECS:-60}            # 未指定时默认 60s，适合短输出模型

# ⚠️ CRITICAL: num_requests 必须由 avg_output_len 推算，绝对不能硬编码为 CONCURRENCY * 200
#
# 【根本原因】benchmark 工具在正式发压前，会先把全部 num_requests 条数据 tokenize 进内存，
# 然后才开始发送第一个请求。对长输入模型（如八字 ~4K tokens/条），tokenize 速率约 300 条/s：
#   num_requests=12000 → 预处理耗时 40s（接近 300s 测试窗口的 13%）
#   num_requests=90000 → 预处理耗时 5min → 测试时间全部浪费，实际发出 0 条有效请求！
#
# 【正确推导】--request-time-limit 才是真正控制测试时长的参数；
# num_requests 只需"大于窗口内最多能完成的请求数"即可：
#   max_completions ≈ CONCURRENCY × TIME_LIMIT / est_avg_e2e
#   NUM_REQUESTS    = max_completions × 3   （3× 安全系数）
#
# 【est_avg_e2e 计算——核心公式】
# ⚠️ 100 tokens/s 是单卡物理峰值，高并发下单请求实际速率 = 总吞吐 / 并发数，远低于此！
#   实测（饱和档）：
#     4B  模型 con=18：731t/s  / 18 ≈ 41 t/s/请求  avg_out=14   → E2E ≈ 0.3s
#     32B 模型 con=30：500t/s  / 30 ≈ 17 t/s/请求  avg_out=183  → E2E ≈ 4.3s
#     72B 模型 con=60：1056t/s / 60 ≈ 18 t/s/请求  avg_out=2157 → E2E ≈ 93s
# 用 avg_output_len 分段代理模型规模（越长输出 → 越大模型 → 并发下速率越低）：
#   avg_out < 100  : per_req_rate = 50 t/s（4B 级快模型）
#   avg_out 100~500: per_req_rate = 20 t/s（中等推理）
#   avg_out > 500  : per_req_rate = 15 t/s（大模型长推理）
# ✅ 若已知先验 E2E（如 vanilla 部署实测），直接赋给 EST_E2E 环境变量跳过推算
NUM_REQUESTS=$(python3 -c "
import math
avg_out = max(1, ${AVG_OUTPUT_LEN})
# 优先使用先验 E2E（从环境变量传入，如 vanilla 实测值）
import os
known_e2e = float(os.environ.get('EST_E2E', '0'))
if known_e2e > 0:
    est_e2e = known_e2e
else:
    # 分段估算：高并发下单请求实际速率（≠ 单卡峰值速率）
    if avg_out < 100:
        per_req_rate = 50   # 4B 级，短输出
    elif avg_out < 500:
        per_req_rate = 20   # 中等推理
    else:
        per_req_rate = 15   # 大模型长推理（70B+）
    est_e2e = max(0.5, avg_out / per_req_rate)
max_comp = ${CONCURRENCY} * math.ceil(${PHASE1_TIME_LIMIT:-300} / est_e2e)
print(max(int(max_comp * 3), ${CONCURRENCY} * 5))
")

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
    --num-requests "${NUM_REQUESTS}" \
    --request-time-limit "${PHASE1_TIME_LIMIT:-300}" \
    --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
    --no-kvcache \
    || echo "⚠️ con=${CONCURRENCY} 异常，继续"

# ⚠️ 档位间冷却：对长输出模型不可省略！
# 不冷却 → 前档在途请求积压 → 后档测量时间窗被拉长/缩短 → throughput 剧烈振荡
sleep "${COOLDOWN_SECS:-60}"

# → 读取结果 → 对照饱和判断规则 → 决定下一档 CONCURRENCY
```

### 每档指标提取

```python
import pandas as pd

def calc_phase1_metrics(csv_path, avg_output_len_phase0: float):
    """
    avg_output_len_phase0: Phase 0 对 old_response 做 tokenize 统计的均值（权威值）。
    ⚠️ 必须传入此参数；绝对不能用 Phase 1 实测的 completion_token_cnt 均值替代，
    原因：Phase 1 饱和档窗口内只有"跑完的"请求被记录，长请求超时丢弃导致实测均值系统性偏低。
    """
    df = pd.read_csv(csv_path)
    df_ok = df[df["status"] == 200].copy()
    df_ok["start_time"] = pd.to_datetime(df_ok["start_time"])
    df_ok["end_time"]   = pd.to_datetime(df_ok["end_time"])
    total_dur = (df_ok["end_time"].max() - df_ok["start_time"].min()).total_seconds()
    decode_throughput = df_ok["completion_token_cnt"].sum() / total_dur

    # 实测 avg_output_len（仅供参考；若与 Phase 0 值偏差 >20%，说明模型行为已发生变化）
    avg_output_len_measured = df_ok["completion_token_cnt"].mean()

    # max_rps_estimate 必须用 Phase 0 权威值作分母，不使用实测值
    max_rps_estimate = decode_throughput / avg_output_len_phase0

    return {
        "decode_throughput":        round(decode_throughput, 2),
        "avg_output_len_phase0":    round(avg_output_len_phase0, 1),   # Phase 0 权威值（用于 max_rps_estimate）
        "avg_output_len_measured":  round(avg_output_len_measured, 1), # Phase 1 实测值（仅供参考）
        "max_rps_estimate":         round(max_rps_estimate, 3),        # = decode_throughput / avg_output_len_phase0
    }
```

### 饱和判断规则（两段式步进）

| 相邻两档吞吐增幅 | 结论 | 下一档并发 |
|----------------|------|-----------|
| **> 10%** | 未饱和 | 分段倍增：con<50 `×2.0`；con 50~200 `×1.5`；con>200 `×1.2` |
| **1%~10%** | 接近饱和 | `current + max(int(current×5%), 10)`（比例小步精查） |
| **< 1%** | ✅ 已饱和 | 停止，记录 `peak_throughput` |

> **为什么要两段式**：小并发（con<50）用 ×2.0 快速定位量级；中等并发（50~200）用 ×1.5 中速逼近；高并发（>200）改用 ×1.2 谨慎推进，防止 200→400 一步跳跃过冲、单档测试耗时过长。进入接近饱和区（增幅 1~10%）后切换为比例步进，精确捕获饱和拐点。
>
> **为什么用比例步进而非固定 +10**：从翻倍跳入大并发区时（如 200→400），+10 仅为 current 的 2.5%，需要 10+ 步才能找到饱和点（每步 ~23min，累计 4+ 小时）。`max(int(current×5%), 10)` 在小并发（con≤200）时等价于 10，保留精度；在大并发（con=400/1000）时自动扩展为 20/50，效率大幅提升。
>
> **步进大小对照**：
>
> | current | step = max(int(current×5%), 10) |
> |---------|-------------------------------|
> | 40 | 10 |
> | 100 | 10 |
> | 200 | 10 |
> | 400 | **20** |
> | 1000 | **50** |
>
> **典型轨迹示例**（最优并发 ≈ 60，小并发模型）：
> `5 → 10 → 20 → 40`（×2.0）`→ 50 → 60 → 70`（+10 比例步进）`→ 增幅 <1%，饱和确认`
>
> **大并发示例**（最优并发 ≈ 420，32B/8TP 模型）：
> `10 → 20 → 40`（×2.0）`→ 60 → 90 → 135 → 200`（×1.5）`→ 240 → 288 → 345 → 414`（×1.2）`→ 434 → 455`（+20 比例步进）`→ 增幅 <1%，饱和确认`
>
> **⚠️ 振荡陷阱（长输出模型 + 时长/冷却不足时）**：
> 吞吐值会在相邻档位间剧烈振荡（如 363→213→413→105），而不是单调递增后趋于平坦。
> 出现振荡时，**不要** 按饱和规则做结论，先检查两个条件：
> 1. `PHASE1_TIME_LIMIT` 是否 ≥ `avg_output_len × 2.5`s？（用 Phase 0 结果计算）
> 2. 档位间是否有 `sleep COOLDOWN_SECS`？（`max(60, avg_output_len / 2)` 秒）
>
> 若两个条件均未满足，需用正确参数重跑。若数据勉强可用，可采用"各档最大 `max_active_requests` 趋于收敛"作为饱和判断的辅助信号（而非 decode_throughput）：当高并发档（如 con=80）的实测活跃并发仍只有 ~30，说明服务器容量瓶颈在并发 30 附近，与哪档 decode_throughput 最高无关。

### Phase 1 结果分析（CLI）

`analyze_peak_finder.py` Phase 1 支持传入 Phase 0 权威值作为 max_rps_estimate 分母：

```bash
# 传入 Phase 0 权威值（推荐）：max_rps_estimate 使用 Phase 0 avg_output_len 作分母
.venv/bin/python3 scripts/analysis/analyze_peak_finder.py \
    --phase 1 \
    --dir "logs/.../con${CONCURRENCY}" \
    --prev-dir "logs/.../con${PREV_CONCURRENCY}" \
    --checkpoint "logs/.../phase1_checkpoint.md" \
    --avg-output-len-phase0 <Phase 0 产出的 avg_tokens>

# 未提供 --avg-output-len-phase0 时，回落到 Phase 1 实测 avg_output_len，
# 并在输出和 checkpoint 中显示 ⚠️ 提示
```

### Phase 1 检查点（写入 `phase1_checkpoint.md`）

```
peak_decode_throughput      = XX tokens/s
avg_output_len (Phase 0 权威) = XX tokens   ← old_response 全量 tokenize（质量检查通过时为权威值）
avg_output_len (Phase 1 实测) = XX tokens   ← 与 Phase 0 差异 >20% 时必须调查根因
Phase 0 vs Phase 1 偏差      = +XX%  ✅/⚠️
avg_output_len (用于计算)    = XX tokens   ← Phase 0（若质量可信）或 Phase 1 实测（若 Phase 0 有缺陷）
max_rps_estimate            = peak_decode_throughput / avg_output_len(用于计算) = XX req/s
max_running_concurrency     = XX
Phase 2 起始 QPS            = max_rps_estimate × 1.2 = XX req/s
Phase 0 数据质量            = [可信 / 有缺陷：原因说明]
```

> **⚠️ avg_output_len 来源必须明确**：checkpoint 必须同时记录 Phase 0 值、Phase 1 实测值，
> 以及**实际用于 max_rps_estimate 计算的值**（两步判断规则见 Phase 0 节）。
> 若 Phase 0 有已知数据缺陷（如 `old_response` 缺少 `ai_deep_content`），必须标注并改用 Phase 1 实测值。

---

## Phase 2：自适应逼近

**模式**：`--request-rate`（定速发压）  
**每档时长**：由 Phase 0 自动推算（`max(1200, int(avg_output_len × 2.5))`s），用户未指定时使用此公式；用户已指定则按指定值  
**起始 QPS**：`max_rps_estimate × 1.2`  
**初始步长**：`max_rps_estimate × 10%`  
**档位间冷却**：由 Phase 0 自动推算（`max(60, int(avg_output_len / 2))`s），用户未指定时使用此公式

> **⚠️ `production_rps` 配置陷阱**：
> `production_rps` 应为上线 Grafana 的实测 RPM ÷ 60（**实际服务速率**），
> **不是** Poisson 插值时设置的 `TARGET_PEAK_RPM`（那是数据集的目标峰值 RPM，与服务实际承载量无关）。
> 例如：`TARGET_PEAK_RPM=256` 不等于 `PRODUCTION_RPS=4.27`——若模型实际产线 RPS 很低（如 0.05），
> 误用 4.27 作为 `production_rps` 会导致 bracket 搜索过早以 4.27 托底，错误地终止收敛。
> 若 production_rps 未知，设为一个安全的小值（如 `0.05`）作为搜索下限，而非从 RPM 换算。

### 执行（单档模板）

```bash
PROBE_QPS=<本档值>
LEVEL_DIR="${OUTPUT_DIR}/phase2_rps${PROBE_QPS}"
mkdir -p "${LEVEL_DIR}"

# ⚠️ NUM_PROMPTS 必须基于实际 DURATION_SECS 计算，不可硬编码 1200
# 公式：RPS × DURATION × 1.1（10% 安全冗余，确保时间到之前不会耗尽请求队列）
# 错误示例：echo "$PROBE_QPS * 1200"  ← 若 DURATION=3600，实际需要 3× 更多，会提前耗尽
NUM_PROMPTS=$(python3 -c "import math; print(math.ceil(float('${PROBE_QPS}') * ${DURATION_SECS} * 1.1))")

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

# COOLDOWN_SECS 由 Phase 0 自动推算（或用户指定）；默认值 60 仅适用于短输出模型
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
> **脚本健壮性（EXIT trap 机制）**：Phase 2 脚本在 `OUTPUT_BASE` 确定后注册 `trap write_exit_checkpoint EXIT`，  
> 无论正常收敛、达到 `MAX_ITERS` 还是被 kill/crash，退出时必然写入 `phase2_checkpoint.md`。  
> - 正常收敛 → checkpoint 标注来源 `normal`，Phase 3 衔接脚本直接读取  
> - 意外退出 → checkpoint 标注 `[EXIT_TRAP]`，以 `LAST_PASS_RPS` 为 `ideal_rps`（保守取 PASS 下界）  
> - 所有档均 FAIL → checkpoint 标注 `[PRODUCTION_FLOOR]`，`ideal_rps = production_rps`  
> Phase 3 衔接脚本作为第二道保险：若检测到 Phase 2 进程已死但无 checkpoint，  
> 自动扫描 `rps*/` 目录并调用 `analyze_peak_finder.py` 推断 `ideal_rps`，写入 `phase2_recovery_checkpoint.md`。  
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
**每档时长**：与 Phase 2 相同（Phase 0 自动推算或用户指定），目标提供比 Phase 2 更稳定的曲线样本  
**档位间冷却**：与 Phase 2 相同（Phase 0 自动推算或用户指定）

```bash
OUTPUT_DIR="logs/${MODEL_NAME}/${MODEL}_phase3_grid_$(date +%Y%m%d)"

for QPS in ${LEVEL_1} ${LEVEL_2} ${LEVEL_3} ${LEVEL_4}; do
    LEVEL_DIR="${OUTPUT_DIR}/qps_${QPS}"
    mkdir -p "${LEVEL_DIR}"
    NUM_PROMPTS=$(echo "$QPS * ${DURATION_SECS}" | bc | awk '{print int($1)+1}')

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

    # COOLDOWN_SECS 由 Phase 0 自动推算（或用户指定）；默认值 60 仅适用于短输出模型
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
| **⚠️ Phase 1 测试窗口全浪费，0 条有效请求发出** | `num_requests` 使用 `CONCURRENCY * 200` 硬编码；benchmark 工具在发压前预 tokenize 全部行数：对长输入模型（~4K tokens/条）12000 条需 40s，90000 条需 5min，超过 300s 时间窗 | **`run_phase1_saturation.sh` 已内置正确公式**，调用时传入 `AVG_OUTPUT_LEN=<Phase 0 值>` 即可；禁止传入 `NUM_REQUESTS_MUL` 硬编码乘数 |
| **⚠️ NUM_REQUESTS 虚高（tokenize 浪费大量时间）或虚低（队列提前耗尽）** | 使用了 `est_e2e = avg_out / 100`（100 t/s 是单卡物理峰值，高并发下实际为 **总吞吐/并发**，72B con=60 实测约 18 t/s/请求，小模型也只有 40 t/s）；100 t/s 对 72B 高估 5×（NUM_REQUESTS 膨胀），同时对 4B 短输出低估（NUM_REQUESTS 不够，队列耗尽）| 按 avg_output_len 分段：`< 100 tokens → 50 t/s；100~500 → 20 t/s；> 500 → 15 t/s`；若有先验 E2E 直接设 `EST_E2E=<实测值>` 环境变量 |
| **⚠️ Phase 2/3 请求队列提前耗尽，测试提前终止** | `NUM_PROMPTS` 硬编码 `PROBE_QPS * 1200`；当 `DURATION_SECS=3600` 时实际需要 3× 更多，约 20min 后队列空，测试提前结束 | `NUM_PROMPTS = ceil(PROBE_QPS × DURATION_SECS × 1.1)`；必须使用实际 `DURATION_SECS` 变量，不能假设 1200 |
| Phase 1 吞吐一直线性增长（无饱和迹象）| 数据集行数不足，`num_requests` 先耗尽导致测试提前结束 | 用上方正确公式重新计算 `NUM_REQUESTS` |
| **⚠️ Phase 2 起始 RPS 偏低（如 0.49），远低于预期（如 0.3×）** | `max_rps_estimate` 用了 Phase 1 实测的 `avg_output_len`（长请求超时丢弃 → 均值偏低），而非 Phase 0 的 `old_response` 权威统计值 | 先做 Phase 0 数据质量检查；若 Phase 0 可信，用 `avg_output_len_phase0` 计算；若 Phase 0 有已知结构缺陷，改用 Phase 1 实测值 |
| **⚠️ Phase 2 START_RPS 高估，启动即崩溃（Phase 1 与 Phase 0 偏差 >40%，且 Phase 0 数据有缺陷）** | `old_response` 未含推理链（如未前置 `ai_deep_content` / 模型升级后格式变化），Phase 0 系统性低估；误用 Phase 0 值导致 Phase 2 在实际 2× 容量处启动 → 过载（status=-3 超 80%，success rate <15%）| 1）确认 Phase 0 数据有结构性缺陷（检查 `old_response` 含 `<think>` 比例）；2）用 Phase 1 实测 `avg_output_len` 重算 `max_rps_estimate`；3）重启 Phase 2 |
| Phase 2 从高 QPS 开始成功率就很低 | `max_rps_estimate` 高估 | 降低起始 QPS 到 `max_rps_estimate × 0.8` |
| Phase 2 找不到 SLA 超标点 | 模型性能很好，SLA 从未触发 | 继续向上探直到 `extreme_rps`，`ideal_rps = extreme_rps` |
| production_rps 未知 | 没有上线 Grafana 数据 | Phase 3 起始点改为 `ideal_rps × 0.5` |
| Phase 2 bracket Pass 后下一档 RPS 反而更低 | auto 脚本复用了 analyze 用旧 bracket 预算的 `[NEXT_RPS]`，LO 已更新但 next_rps 未重算 | bracket 更新后在 shell 层重新计算几何中点（见上方⚠️陷阱），不复用 analyze 打印值 |
| Phase 1 decode_throughput 在相邻档位间剧烈振荡（363→213→413→105）| 时长不足（300s << E2E）+ 无档位间冷却：每档完成样本 <50 条，前档在途请求拉长/缩短后档测量时间窗 | 1）`PHASE1_TIME_LIMIT = max(300, avg_output_len × 2.5)`；2）档位间加 `sleep COOLDOWN_SECS`；若数据勉强可用，改用 `max_active_requests` 趋于收敛作为饱和判断辅助信号 |
| Phase 2 低 QPS 反而比高 QPS 延迟更高（"倒挂"）| 冷却不足导致测试污染：上一档在途请求堆积进入下一档测试窗口 | 终止测试等服务完全空闲，使用 Phase 0 自动推算的 `COOLDOWN_SECS`（≥ `avg_output_len / 2`s）重新启动 |
| `PRODUCTION_RPS` 设为 `TARGET_PEAK_RPM / 60`（如 4.27）导致 bracket 过早收敛 | 混淆"数据集目标 RPM"与"服务实际 RPS"：Poisson 插值目标 RPM 是数据集制备参数，不代表模型实际能承载的 RPS | `production_rps` 取 Grafana 实测 RPM ÷ 60；未知时设保守小值（如 0.05）作为搜索下限 |
| Phase 2 有 `rps*/` 目录但无 `phase2_checkpoint.md`，Phase 3 衔接脚本等 24h 后超时退出 | Phase 2 脚本在 bracket 未收敛时被 kill/崩溃，checkpoint 写入从未触发；旧版衔接脚本仅依赖 checkpoint 文件存在 | **新版双保险**：① Phase 2 脚本已加 `trap write_exit_checkpoint EXIT`，退出时必然写入 checkpoint（标注 `[EXIT_TRAP]`）；② Phase 3 衔接脚本检测到 Phase 2 进程已死后自动扫描 `rps*/` 目录，用 `analyze_peak_finder.py` 找最高 PASS 档写入 `phase2_recovery_checkpoint.md`。手动恢复步骤详见 Phase 2 执行注意事项。 |
