# 设计文档：model-eval-report Skill

> 写于 2026-03-16 | 状态：已实现并验证（tianji-querysafety-4b-v2-3，2026-03-16）

---

## 背景

当前评估流程（`model-evaluation-workflow` Step 0~6）在 Step 6 结束后只输出一行文字结论，实验数据散落在多个 `results/<model>_<date>/REPORT.md` 中。AI-infra 在完成评估后没有一份面向交付的完整报告。

`model-eval-report` Skill 作为 Step 7，在 Step 6 完成后触发，读取已有产物，生成覆盖"部署配置 → 数据背景 → 测试结论 → 资源建议"的完整交付文档。

---

## 一、职责边界

| 项 | 说明 |
|----|------|
| **触发方式** | 独立可调用 + 被 `model-evaluation-workflow` Step 7 编排调用 |
| **主要输入** | `results/models/<model>/model-context.md`（结构化上下文）+ 各实验 `REPORT.md` |
| **输出** | `results/models/<model-name>/EVAL_REPORT.md` |
| **不做的事** | 不重跑分析，不修改现有 REPORT.md，不读原始 logs/ 日志 |

---

## 二、model-context.md —— 结构化上下文文件

### 设计原则

- **与 `progress.md` 并行存在，职责不重叠**
  - `progress.md`：AI 会话叙述日志，供续跑定位，自由文本
  - `model-context.md`：结构化字段，供报告生成读取，字段固定
- **跨 Step 增量写入**：各 Step 完成后追加/更新对应字段，不要求 Step 0 一次性写完
- **存放位置**：`results/models/<model-name>/model-context.md`（与最终 EVAL_REPORT.md 同目录）

### 字段来源与写入时机

| 字段 | 写入时机 | 来源 |
|------|---------|------|
| `model_name` | Step 0 | 用户/部署规格 |
| `model_path` | Step 0 | 部署规格 |
| `image` | Step 0 | 部署规格 |
| `tp_size` / `dp_size` | Step 0 | 部署规格 |
| `gpu_ids` / `gpu_type` | Step 0 | `nvidia-smi` |
| `max_completion_tokens` | Step 0 | 业务推理参数（可选）|
| `model_type` | Step 2 | `llm-service-probing` 输出 |
| `usage_scenario` | Step 2 | `llm-service-probing` 输出 |
| `business_peak_rpm` | Step 3 | 数据集分析 |
| `dataset_path` | Step 3 | `traffic-dataset-prep` 输出 |
| `endpoint_url` | Step 4 | 用户提供（人工断点后） |
| `baseline_latency_s` | Step 4 | 连通性验证 |
| `replay_success_rate` | Step 5 | 回放压测结论 |
| `replay_ttft_p90_s` | Step 5 | 回放压测结论 |
| `replay_e2e_p90_s` | Step 5 | 回放压测结论 |
| `sla_max_qps` | Step 6 | QPS 拐点报告 |
| `sla_threshold` | Step 6 | QPS 拐点报告（模型特定） |
| `inflection_type` | Step 6 | 拐点分析（软/硬拐点） |

### 文件格式示例

```yaml
# model-context.md
# 模型评估结构化上下文 — 增量写入，勿手动修改关键字段

model_name: tianji-querysafety-4b-v2-3
model_path: /mnt/ai-llm/tianji_query_safety/v2p3_ep1
image: reg.xxwolo.com/ai/lmsysorg-sglang:latest
tp_size: 4
dp_size: 1
gpu_ids: "0,1,2,3"
gpu_type: L20
max_completion_tokens: 256

model_type: 安全拦截模型
usage_scenario: 对用户输入进行违规检测，返回 {"label": "...", "instruction": "..."}

business_peak_rpm: 2168
dataset_path: datas/output_tianji/tianji-querysafety-4b-v2-3_peak30min.csv

endpoint_url: https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23/v1/chat/completions
baseline_latency_s: 0.22

replay_success_rate: 100.0
replay_ttft_p90_s: 0.243
replay_e2e_p90_s: 0.257

sla_max_qps: 8.0
sla_threshold: "E2E P95 ≤ 400ms"
inflection_type: 软拐点（P95 超标，P90 达标）
```

---

## 三、资源建议计算逻辑

```
业务峰值 req/s  = business_peak_rpm ÷ 60
最低实例数      = ceil(业务峰值 req/s ÷ sla_max_qps)
推荐实例数      = ceil(业务峰值 req/s ÷ (sla_max_qps × 0.9))   # 90% 负载率，留 10% 余量
GPU 总数        = 推荐实例数 × tp_size
单实例覆盖率    = sla_max_qps × 60 ÷ business_peak_rpm × 100%
```

> **系数说明**：压测数据集本身已基于业务峰值窗口构建（含泊松放大），SLA 拐点已在接近真实峰值的条件下测得，因此安全余量取 10% 即可。

**示例（tianji-querysafety-4b）**：
```
业务峰值 = 2168 RPM = 36.1 req/s
SLA 合规 QPS = 8.0 req/s
最低实例数 = ceil(36.1 / 8.0) = 5
推荐实例数 = ceil(36.1 / 7.2) = 6
GPU 总数   = 6 × 4 = 24 卡
单实例覆盖 = 480 / 2168 = 22%
```

---

## 四、EVAL_REPORT.md 报告结构

```markdown
# <model_name> 模型评估报告

**生成日期**：YYYY-MM-DD
**评估周期**：YYYY-MM-DD ~ YYYY-MM-DD

---

## 【摘要】上线建议（业务方阅读）

| 维度 | 结论 |
|------|------|
| **上线建议** | ✅ 可上线 / ⚠️ 有条件上线 / ❌ 暂不建议 |
| **单实例承载能力** | X req/s（Y RPM）@ SLA 达标 |
| **当前业务覆盖率** | 单实例覆盖 Z%（业务峰值 W RPM）|
| **推荐部署规模** | N 个实例 × M 张 GPU（含 20% 安全余量）|
| **风险提示** | 如有说明，否则"无" |

---

## 【技术详情】AI-infra 存档

### 1. 部署配置

| 项目 | 值 |
|------|----|
| 模型路径 | `<model_path>` |
| 推理镜像 | `<image>` |
| 并行配置 | TP=<n> / DP=<n> |
| GPU 型号 | <gpu_type>，共 <tp×dp> 卡 |
| 最大输出 Token | <max_completion_tokens> |

### 2. 数据背景

| 项目 | 值 |
|------|----|
| 模型类型 | <model_type> |
| 使用场景 | <usage_scenario> |
| 业务峰值 | <business_peak_rpm> RPM（<req/s> req/s）|
| 压测数据集 | <dataset_path> |
| 服务地址 | `<endpoint_url>` |

### 3. 回放压测结论

| 指标 | 测试值 | SLA 门限 | 结果 |
|------|--------|---------|------|
| 请求成功率 | <replay_success_rate>% | ≥ 99% | ✅ / ❌ |
| TTFT P90 | <replay_ttft_p90_s>s | ≤ 1.5s | ✅ / ❌ |
| E2E P90 | <replay_e2e_p90_s>s | 模型特定 | ✅ / ❌ |

### 4. QPS 拐点结论

| 配置 | SLA 合规最大 QPS | 拐点类型 |
|------|----------------|---------|
| TP=<n>×1 实例 | <sla_max_qps> req/s | <inflection_type> |

**SLA 基准**：<sla_threshold>

### 5. 实验数据索引

| 实验 | 类型 | 目录 |
|------|------|------|
| <实验名> | 回放压测 | `results/<dir>/` |
| <实验名> | QPS 拐点扫描 | `results/<dir>/` |
```

---

## 五、输出位置

```
results/
  models/
    <model-name>/
      model-context.md     ← 增量写入（Step 0~6）
      EVAL_REPORT.md       ← model-eval-report Skill 产出（Step 7）
```

`results/<model>_<date>/` 下的单次实验 REPORT.md 保持原位不变，EVAL_REPORT.md 作为跨实验汇总层。

---

## 六、与 model-evaluation-workflow 的集成

### Step 0~6 新增动作

每步完成后，在写 `progress.md` 的同时，**追加/更新 `model-context.md` 对应字段**（见第二节字段来源表）。

### 新增 Step 7

```
Step 6 ✅ 分析归档
    ↓
Step 7  生成评估报告  ← 调用 model-eval-report Skill
    ↓
【评估完成 ✅】<model-name>
  评估报告：results/models/<model-name>/EVAL_REPORT.md
  上线建议：✅ 可上线
  推荐规模：N 实例 × M 张 GPU
```

**Step 7 跳过条件**：
```bash
ls results/models/<model-name>/EVAL_REPORT.md  # 已存在且 Step 6 无更新
```

**progress.md 写入**：
```markdown
### Step 7 ✅ 生成评估报告（YYYY-MM-DD）
- 报告路径：results/models/<model-name>/EVAL_REPORT.md
- 上线建议：✅ 可上线
- 推荐规模：<N> 实例 × <M> 张 GPU
```

---

## 七、TDD 交付标准

按 `writing-skills` 规范：

1. **RED**：无 Skill 时，用 tianji 已有产物手动整理一份报告，记录耗时与遗漏字段
2. **GREEN**：写 SKILL.md，用 tianji 产物（补写 model-context.md + 4 份 REPORT.md）生成 EVAL_REPORT.md，验证两层结构完整
3. **REFACTOR**：补充边界场景
   - 无回放数据时（仅 QPS 扫描）
   - `business_peak_rpm` 未知时（提示用户填写，或在摘要层标注"待补充"）
   - 多组 QPS 对比（如 4TP vs 4DP）时如何选取 `sla_max_qps`

**验证模型**：`tianji-querysafety-4b-v2-3`（产物最完整，有回放 + QPS 拐点 + TP vs DP 对比）
