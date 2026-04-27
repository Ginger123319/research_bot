# QPS Peak Finder 设计文档

**日期**：2026-03-18  
**状态**：已批准，待实践验证  
**关联 Skill**：`.cursor/skills/qps-peak-finder/SKILL.md`

---

## 背景与动机

现有 `qps-benchmark-sweep` Skill 采用均匀/密度加权网格扫描，存在以下局限：

1. **上限不明**：新模型上线前不知道极限 QPS，网格范围难以设置
2. **无法获得极限推理能力**：缺少「硬件在当前部署配置下的极限吞吐」基准
3. **网格盲扫效率低**：在无意义区间浪费大量测试时间（数小时）

本设计提出「**先顶峰、后摸底**」的自适应探测思路，用更少档位获得两个关键锚点：
- **极限 RPS**：服务在当前硬件下的绝对上限
- **理想 RPS**：满足 SLA 约束的最大 RPS

---

## 整体架构

```
┌──────────────────────────────────────────────────────┐
│  Phase 1: 饱和探测                                    │
│  工具模式：--max-concurrency（不限速，固定并发）        │
│  目标：peak_decode_throughput → max_rps_estimate      │
│  耗时预估：3~5 档 × ~10min = 30~50min                 │
├──────────────────────────────────────────────────────┤
│  Phase 2: 自适应逼近                                  │
│  工具模式：--request-rate（限速），每档 1200s          │
│  目标①：极限 RPS（吞吐拐点）                          │
│  目标②：理想 RPS（SLA 合规边界）                      │
│  机制：决策表驱动 + 人工检查点（可选）                 │
│  耗时预估：3~6 档 × 20min = 60~120min                 │
├──────────────────────────────────────────────────────┤
│  Phase 3: 上线验证网格                                │
│  工具模式：--request-rate，每档 2700s（45min）         │
│  目标：[production_rps, ideal_rps] 均匀 4 档          │
│  输出：图表 + REPORT.md（交 qps-sweep-comparison 处理）│
└──────────────────────────────────────────────────────┘
```

### 与现有 Skill 的关系

| Skill | 定位 |
|-------|------|
| `qps-benchmark-sweep` | 均匀/密度网格扫描，适合已知拐点大致区间时精查 |
| **`qps-peak-finder`**（本设计）| 新模型冷启动，自适应找极限 RPS + 理想 RPS |
| `qps-sweep-comparison` | 两者的下游分析/可视化层 |

> 当前定位：与 `qps-benchmark-sweep` 并列备选；实践验证后考虑替换。

---

## Phase 1：饱和探测

### 原理

使用 `--max-concurrency N` 模式（不设请求速率，固定并发窗口），逐步提升并发数，观察 `decode_throughput` 何时不再增长。

**核心公式**：
```
max_rps_estimate = peak_decode_throughput / avg_output_len
```

### 执行方式

每档固定时长 **300s（5min）**，用 `--request-time-limit` 控制，每档独立运行后读取结果，再根据饱和判断规则决定下一档并发数（Agent 逐档决策，非预设序列）。

起始并发：`5`

```bash
# 单档模板（Agent 每轮调整 CONCURRENCY 后执行）
LEVEL_DIR="${OUTPUT_DIR}/phase1_con${CONCURRENCY}"
mkdir -p "${LEVEL_DIR}"
/path/to/llm_benchmark \
    --max-concurrency ${CONCURRENCY} \
    --num-requests $((CONCURRENCY * 200)) \
    --request-time-limit 300 \
    --no-kvcache \
    --output-dir "${LEVEL_DIR}" \
    ...
# → 读取结果 → 对照饱和判断规则 → 决定下一档 CONCURRENCY
```

### 每档指标计算

```python
import pandas as pd
df = pd.read_csv("phase1_con{N}/exp_name.csv")
df_ok = df[df["status"] == 200]
total_dur = (pd.to_datetime(df_ok["end_time"]).max() -
             pd.to_datetime(df_ok["start_time"]).min()).total_seconds()
decode_throughput = df_ok["completion_token_cnt"].sum() / total_dur
avg_output_len    = df_ok["completion_token_cnt"].mean()
max_rps_estimate  = decode_throughput / avg_output_len
```

### 饱和判断规则（两段式步进）

| 相邻两档吞吐增幅 | 结论 | 下一档并发 |
|----------------|------|-----------|
| **> 10%** | 未饱和 | `current × 2`（翻倍快速逼近） |
| **1%~10%** | 接近饱和 | `current + 10`（线性小步精查） |
| **< 1%** | ✅ 已饱和 | 停止，记录 `peak_throughput`，进入 Phase 2 |

> **为什么要两段式**：纯翻倍步进太粗，会跳过真实饱和点。例如最优并发为 60，测完 40 直接跳 80 会漏掉这个峰值。进入接近饱和区后改为 +10 线性步进，精确捕获饱和拐点。
>
> **典型轨迹**（最优并发 ≈ 60）：
> `5 → 10 → 20 → 40`（增幅 >10%，翻倍）`→ 50 → 60 → 70`（增幅进入 1~10%，+10）`→ 发现 60→70 增幅 <1%，饱和确认`

### Phase 1 检查点输出

```
peak_decode_throughput  = XX tokens/s
avg_output_len          = XX tokens
max_rps_estimate        = XX req/s
max_running_concurrency = XX        ← max-running-requests 参考值
建议 Phase 2 起始 QPS   = max_rps_estimate × 1.2
```

---

## Phase 2：自适应逼近

### 目标

| 目标 | 定义 | 判断依据 |
|------|------|---------|
| **极限 RPS** | 服务刚开始无法消化请求的临界点 | `decode_throughput` 增长停滞 + `max_active_requests` 持续堆积 |
| **理想 RPS** | 首个 SLA 超标档位的前一档 | TTFS P90 > 1500ms 或 E2E P90 > 150s（或模型特定阈值）|

### 执行参数

- 模式：`--request-rate`
- 每档时长：**1200s（20min）**
- 起始 QPS：`max_rps_estimate × 1.2`
- 初始步长：`max_rps_estimate × 10%`

### 每档指标计算

```python
decode_throughput   = df_ok["completion_token_cnt"].sum() / total_duration
# max_active_requests: 同时在途请求数峰值（从 start_time/end_time 重建并发曲线）
ttfs_p90            = df_ok["ttfs"].quantile(0.9)
e2e_p90             = df_ok["e2e"].quantile(0.9)
```

### 决策表

| 指标组合 | 判断 | 下一步 QPS |
|---------|------|-----------|
| SLA ✅ + 吞吐增幅 > 5% | 未到极限，未到理想上限 | `+step` |
| SLA ✅ + 吞吐增幅 < 5% + 并发堆积 | 接近极限 RPS | `+step/2`，缩小步长精查 |
| SLA ✅ + 吞吐不再增长 + 并发持续高位 | **极限 RPS 锚定** | 记录；继续向上找 SLA 边界 |
| **SLA ❌ 首次超标** | **理想 RPS = 本档 - 1 step** | 在前一档与本档之间做 1~2 次二分精查 |
| SLA ❌ + 吞吐停止增长 | 两目标同时锚定 | 结束 Phase 2 |

### 人工检查点格式

每档完成后写入 `phase2_checkpoint.md`：

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

### Phase 2 停止条件

满足以下任一即停止：
1. 极限 RPS ✅ 且 理想 RPS ✅（两目标均已锚定）
2. QPS 已降至 `production_rps` 以下仍未找到理想 RPS → `ideal_rps = production_rps`（托底）

---

## Phase 3：上线验证网格

### QPS 档位

```python
import numpy as np
levels = np.linspace(production_rps, ideal_rps, 4)
# 例：production=0.5, ideal=1.2 → [0.50, 0.73, 0.97, 1.20]
```

### 执行参数

- 每档时长：**2700s（45min）**
- 档位间冷却：60~90s
- 输出目录：`logs/${MODEL}_phase3_grid_$(date +%Y%m%d)/`

### 完成后

输出目录直接交给 `qps-sweep-comparison` Skill 处理，生成：
- `plot_qps.html` / `plot_throughput.html` / `plot_latency_2d.html`
- `REPORT.md`

---

## SLA 基准（继承自 qps-sweep-comparison）

### 通用基准

| 指标 | 基准 | 说明 |
|------|------|------|
| TTFS P90 | ≤ 1500 ms | 首句延迟，用户感知最直接 |
| E2E P90 | ≤ 150 s | 完整响应时间上限 |

### 模型特定基准（按需补充）

| 模型 | 指标 | 基准 |
|------|------|------|
| tianji（安全检测）| 整体时长 P95 | ≤ 400 ms |
| （新模型按需补充）| — | — |

---

## 整体产出汇总

| 产出 | 来源阶段 |
|------|---------|
| `peak_decode_throughput` | Phase 1 |
| `max_running_concurrency` | Phase 1 |
| `extreme_rps`（极限 RPS） | Phase 2 |
| `ideal_rps`（理想 RPS） | Phase 2 |
| SLA 曲线图表 + REPORT.md | Phase 3 → qps-sweep-comparison |

---

## 待验证项

- [ ] Phase 1 两段式步进策略是否适合长输出模型（长 e2e 导致并发堆积失真，可能需要调整 +10 步长或时长）
- [ ] Phase 2 初始步长 10% 是否过大（若极限 RPS 与 max_rps_estimate 偏差大）
- [ ] production_rps 托底逻辑：实际生产 RPM 需在开始前从 Grafana 确认
