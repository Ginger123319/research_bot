# qps-peak-finder-analysis 设计文档

**日期**：2026-03-20  
**作者**：AI  
**状态**：已批准，待实现

---

## 背景与动机

`qps-peak-finder` Skill 完成三阶段执行后产出三类数据目录：

| 阶段 | 子目录命名 | 模式 | x 轴维度 |
|------|-----------|------|---------|
| Phase 1 | `con100/`, `con200/`... | `--max-concurrency` | 并发数 |
| Phase 2 | `rps5.896/`, `rps7.221/`... | `--request-rate` | QPS |
| Phase 3 | `qps0.667/`, `qps2.982/`... | `--request-rate` | QPS |

现有 `qps-sweep-comparison` Skill 只处理 Phase 3 单阶段输出，存在三个空白：

1. **Phase 2 + Phase 3 合并**：两者均为 `--request-rate` 格式、完全兼容，合并后可绘制从生产负载到边界的完整容量曲线（更密集的数据点）
2. **极限承载并发估算**：Phase 1 checkpoint 记录的是客户端并发数设定值，非服务端实际 in-flight 数。需用 Little's Law 从 Phase 1 CSV 中计算真实服务端承载并发
3. **三锚点对照表**：REPORT.md 缺少将极限 RPS / 理想 RPS / 生产 RPM 三个操作点并排呈现的结构

---

## 决策记录

| 问题 | 选项 | 决策 |
|------|------|------|
| Phase 2 数据纳入容量曲线？ | 仅 Phase 3 / Phase 2+3 合并 | **Phase 2+3 合并** |
| Phase 1 数据呈现方式？ | 出图 / 文字摘要 / 不写 | **REPORT.md 文字摘要（含 Little's Law 估算）** |
| REPORT.md 结构 | 全新结构 / 双层结构 / 扩展模板 B | **扩展模板 B（QPS 拐点报告），加 peak-finder 专属节** |
| 落地位置 | 扩展现有 SKILL / 新建 SKILL | **新建 `qps-peak-finder-analysis` SKILL** |
| SLA 指标 | 硬编码 TTFS/E2E | **动态读取 sla_config，沿用 qps-sweep-comparison 的 custom 机制** |

---

## 新 Skill：`qps-peak-finder-analysis`

### 触发时机

`qps-peak-finder` 三阶段全部完成后调用（Phase 3 日志出现 "Phase 3 Complete"）。

### 工作流（5 步）

```
Step 1  Little's Law 估算极限承载并发
Step 2  合并 Phase 2 + Phase 3 数据（cp -rl 硬链接）
Step 3  qps-sweep-comparison → 容量曲线图表
Step 4  生成 REPORT.md（模板 B 扩展版，三锚点对照表）
Step 5  归档：更新 model-context.md / results/README.md / INDEX.yaml
```

---

### Step 1 — Little's Law 估算极限承载并发

**档位选取**：Phase 1 饱和确认档（最后一档，即吞吐增幅跌破阈值的那档）

```python
import pandas as pd, glob, os

def estimate_server_concurrency(phase1_con_dir: str, max_rps_estimate: float) -> dict:
    """
    phase1_con_dir: Phase 1 饱和确认档目录，如 logs/.../con400/
    max_rps_estimate: 该档 checkpoint 中的 max_rps_estimate
    """
    csv_files = glob.glob(os.path.join(phase1_con_dir, "*.csv"))
    # 排除 *.argv.csv
    csv_files = [f for f in csv_files if not f.endswith(".argv.csv")]
    df = pd.read_csv(csv_files[0])
    df_ok = df[df["status"] == 200].copy()
    df_ok["start_time"] = pd.to_datetime(df_ok["start_time"])
    df_ok["end_time"]   = pd.to_datetime(df_ok["end_time"])
    df_ok["e2e_s"] = (df_ok["end_time"] - df_ok["start_time"]).dt.total_seconds()

    mean_e2e = df_ok["e2e_s"].mean()
    l_server = max_rps_estimate * mean_e2e   # Little's Law: L = λ × W

    return {
        "max_rps_estimate":    round(max_rps_estimate, 4),
        "mean_e2e_s":          round(mean_e2e, 2),
        "server_concurrency":  round(l_server, 1),
    }
```

**输出字段**（写入 `model-context.md`）：
```yaml
extreme_rps: <max_rps_estimate>
server_concurrency_at_extreme: <L_server>
```

---

### Step 2 — 合并 Phase 2 + Phase 3 数据

```bash
MERGED="logs/${MODEL}_phase23_merged_${DATE}"
mkdir -p "$MERGED"

# Phase 2 档位（rpsX.XXXX/ 子目录）
for d in logs/${MODEL}-phase2_*/rps*/; do
    cp -rl "$d" "$MERGED/$(basename $d)"
done

# Phase 3 档位（qpsX.XXXX/ 子目录）
for d in logs/${MODEL}-phase3_*/qps*/; do
    cp -rl "$d" "$MERGED/$(basename $d)"
done
```

> ⚠️ 使用 `cp -rl`（硬链接）而非符号链接：`Path.glob("**/*.csv")` 默认不追踪指向目录的符号链接。

合并后直接传给 `qps-sweep-comparison` Skill，目录中同时含 Phase 2 探测点和 Phase 3 验证网格点，曲线更完整。

---

### Step 3 — 容量曲线图表

沿用 `qps-sweep-comparison` Skill 的 YAML 配置方式：

```yaml
# configs/models/<model>/<tp>_peak_finder_analysis.yaml
groups:
  - label: "<model> <TP>×1实例"
    dir: "logs/<model>_phase23_merged_<date>"

x_key: request_rate
output_dir: "results/<model>_peak_finder_<date>"

sla_config:
  ttfs_p90: 1.5
  e2e_p90: 150.0
  success_rate: 0.99
  # 模型特定阈值（如 tianji 使用 E2E P95 ≤ 400ms）：
  # custom:
  #   - metric: e2e
  #     percentile: 95
  #     limit: 0.4
  #     label: "E2E P95"
```

多部署对比（8TP vs 4TP）时同理，groups 列表各加一条，label 区分。

---

### Step 4 — REPORT.md（模板 B 扩展版）

在标准 QPS 拐点报告模板 B 基础上，**新增 `§peak-finder 专属节`**：

```markdown
## §0 Peak Finder 三锚点摘要

| 操作点 | RPS | 服务端承载并发 | [模型SLA指标1] | [模型SLA指标2] | 成功率 |
|--------|-----|--------------|--------------|--------------|--------|
| 极限 RPS（Phase 1）| <extreme_rps> | <server_concurrency>（Little's Law）| 不适用（饱和区）| — | — |
| 理想 RPS（Phase 2 收敛）| <ideal_rps> | <L_ideal> | <TTFS P90> | <E2E P90> | <成功率> |
| 生产 RPM（可选）| <prod_rps> | — | <TTFS P90> | <E2E P90> | <成功率> |

> Little's Law：L = λ × W，W = 饱和档 mean E2E，反映服务端实际 in-flight 请求数

## §1 Phase 1 — 饱和探测摘要

| 并发档 | decode_throughput | max_rps_estimate | 判断 |
|--------|-----------------|-----------------|------|
| con50  | ... | ... | 继续 |
| con100 | ... | ... | 继续 |
| **con400** | **<峰值>** | **<extreme_rps>** | **✅ 饱和确认** |

峰值 decode_throughput = <X> tokens/s，极限 RPS = <extreme_rps> req/s

## §2 Phase 2 — 自适应逼近过程

| 轮次 | RPS | [SLA指标] | 结论 | bracket |
|------|-----|----------|------|---------|
| 1 | ... | ... | ❌ | HI=... |
| ... | | | | |
| N | <ideal_rps> | <值> | ✅ 收敛 | [lo, hi] 宽 <X>% |

## §3 Phase 3 — 上线验证网格（容量曲线）

[由 qps-sweep-comparison 生成，嵌入图表路径]

（以下沿用标准模板 B 结构）
```

**SLA 指标列动态生成规则**：
- 从运行时 `sla_config` 读取（YAML 配置文件）
- 通用基准：TTFS P90 + E2E P90 + 成功率
- 模型特定：按 `sla_config.custom` 替换或追加

---

### Step 5 — 归档

与现有归档规范一致，额外写入两个新字段：

```yaml
# model-context.md 追加
extreme_rps: <x>
server_concurrency_at_extreme: <n>
```

---

## 受影响的现有 Skill

### `model-evaluation-workflow` — Step 5 & Step 6

**Step 5** 增加路径分支：
```
路径 A（已知大致拐点）→ qps-benchmark-sweep Skill
路径 B（拐点完全未知）→ qps-peak-finder Skill
```

**Step 6** 增加分析路径对应：
```
Step 5 路径 A → qps-sweep-comparison Skill
Step 5 路径 B → qps-peak-finder-analysis Skill（新）
```

**Step 6 `model-context.md` 追加字段** 新增两个可选字段：
```yaml
extreme_rps: <x>                     # 可选，peak-finder 时有
server_concurrency_at_extreme: <n>   # 可选，peak-finder 时有
```

### `model-eval-report` — Step 2 & Step 5 模板

**Step 2** 字段列表新增（可选）：
```yaml
extreme_rps: <x>
server_concurrency_at_extreme: <n>
```

**Step 5 模板** §4（QPS 拐点结论）新增可选行：
```markdown
| 极限 RPS（硬件上限）| <extreme_rps> req/s | 饱和测试（Phase 1）|
| 服务端承载并发（极限）| <server_concurrency_at_extreme> | Little's Law 估算 |
```

---

## 文件变更清单

| 操作 | 路径 |
|------|------|
| 新建 | `.cursor/skills/qps-peak-finder-analysis/SKILL.md` |
| 更新 | `.cursor/skills/model-evaluation-workflow/SKILL.md`（Step 5&6） |
| 更新 | `.cursor/skills/model-eval-report/SKILL.md`（Step 2 + 模板 §4） |
