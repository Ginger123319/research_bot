---
name: model-eval-report
description: Use when a model evaluation is complete and you need to generate a comprehensive delivery report — reading model-context.md and individual REPORT.md files to produce a two-layer EVAL_REPORT.md covering deployment config, business data background, benchmark conclusions, and resource recommendations.
---

# Model Eval Report Skill

## 概述

读取已有评估产物，生成面向交付的完整评估报告 `EVAL_REPORT.md`。

**两层结构**：
- **摘要层**：业务方阅读，一句话结论 + 资源建议
- **技术层**：AI-infra 存档，部署配置 + 数据背景 + 实验结论 + 数据索引

**不做的事**：不重跑分析，不修改现有 REPORT.md，不读原始 logs/

---

## 触发条件

- Step 6（结果分析归档）完成后，作为 `model-evaluation-workflow` Step 7 被调用
- 也可单独触发：`results/models/<model-name>/` 目录下存在 `model-context.md` 即可运行

---

## 输入文件

| 文件 | 路径 | 用途 |
|------|------|------|
| `model-context.md` | `results/models/<model>/model-context.md` | 部署配置、业务背景、各步结论（结构化）|
| 各实验 `REPORT.md` | `results/<model>_<date>/REPORT.md` | 回放压测 / QPS 拐点详细指标 |

---

## Step 1：定位输入文件

```bash
# 确认 model-context.md 存在
ls results/models/<model-name>/model-context.md

# 扫描该模型的所有实验报告
ls results/<model-name>_*/REPORT.md
```

若 `model-context.md` 不存在：
- 若在 `model-evaluation-workflow` Step 7 中调用 → 说明前序步骤未正确写入，回到 Step 0 检查
- 若独立触发 → 提示用户按以下格式手动创建 `model-context.md`（见 Step 2）

---

## Step 2：读取 model-context.md

读取以下字段（字段含义见 `clingo/docs/designs/2026-03-16-model-eval-report-design.md`）：

```yaml
# 部署配置字段
model_name / model_path / image / tp_size / dp_size / gpu_ids / gpu_type / max_completion_tokens

# 数据背景字段
model_type / usage_scenario / business_peak_rpm / dataset_path / endpoint_url / baseline_latency_s

# 测试结论字段
replay_success_rate / replay_ttft_p90_s / replay_e2e_p90_s
sla_max_qps / sla_threshold / inflection_type
```

**缺失字段处理**：
- `business_peak_rpm` 缺失 → 询问用户，或在摘要层标注"待补充，无法计算资源建议"
- `replay_*` 缺失 → 说明无回放测试，摘要层注明"仅 QPS 扫描，无回放验证"
- `sla_max_qps` 缺失 → 说明 Step 6 未完成，提示先完成结果分析

---

## Step 3：读取实验 REPORT.md，补充细节

从各实验 REPORT.md 提取以下内容补充到报告：

| 提取内容 | 用途 |
|---------|------|
| SLA 基准表（模型特定阈值）| 技术层第 4 节 |
| 各档位明细表（QPS / TTFT / E2E）| 技术层第 4 节（可引用原表或摘录拐点区间）|
| 扩容建议 / 根因分析 | 技术层第 4 节备注 |
| 实验目录名 + 实验类型 | 技术层第 5 节索引 |

多组对比实验（如 4TP vs 4DP）：以最优配置的 `sla_max_qps` 作为资源计算依据，在技术层注明对比结论。

---

## Step 4：计算资源建议

```
业务峰值 req/s  = business_peak_rpm ÷ 60
最低实例数      = ceil(业务峰值 req/s ÷ sla_max_qps)
推荐实例数      = ceil(业务峰值 req/s ÷ (sla_max_qps × 0.9))
GPU 总数        = 推荐实例数 × tp_size
单实例覆盖率    = round(sla_max_qps × 60 ÷ business_peak_rpm × 100, 1)%
```

> 系数 0.9（90% 负载率）：压测数据集已基于业务峰值窗口构建，拐点已在接近真实峰值的条件下测得，10% 余量已足够。

**上线建议判断逻辑**：
- 回放成功率 ≥ 99% AND QPS 拐点明确 → ✅ 可上线
- 回放成功率 ≥ 99% 但无 QPS 拐点数据 → ⚠️ 有条件上线（资源建议待补充）
- 回放成功率 < 99% 或 SLA 失败 → ❌ 暂不建议上线，说明原因

---

## Step 5：生成 EVAL_REPORT.md

输出路径：`results/models/<model-name>/EVAL_REPORT.md`

按以下模板填写：

```markdown
# <model_name> 模型评估报告

**生成日期**：YYYY-MM-DD
**评估周期**：<最早实验日期> ~ <最近实验日期>

---

## 【摘要】上线建议

| 维度 | 结论 |
|------|------|
| **上线建议** | ✅ 可上线 / ⚠️ 有条件上线 / ❌ 暂不建议 |
| **单实例承载能力** | <sla_max_qps> req/s（<sla_max_qps×60> RPM）@ SLA 达标 |
| **当前业务覆盖率** | 单实例覆盖 <单实例覆盖率>%（业务峰值 <business_peak_rpm> RPM）|
| **推荐部署规模** | <推荐实例数> 个实例 × <GPU总数÷推荐实例数> 张 <gpu_type>（<GPU总数> 卡，含 10% 余量）|
| **风险提示** | <如有则说明，否则填"无"> |

---

## 【技术详情】

### 1. 部署配置

| 项目 | 值 |
|------|----|
| 模型路径 | `<model_path>` |
| 推理镜像 | `<image>` |
| 并行配置 | TP=<tp_size> / DP=<dp_size> |
| GPU 型号 | <gpu_type>，GPU ID：<gpu_ids> |
| 最大输出 Token | <max_completion_tokens> |
| 服务地址 | `<endpoint_url>` |

### 2. 数据背景

| 项目 | 值 |
|------|----|
| 模型类型 | <model_type> |
| 使用场景 | <usage_scenario> |
| 业务峰值 | <business_peak_rpm> RPM（<req/s> req/s）|
| 压测数据集 | `<dataset_path>` |

### 3. 回放压测结论

| 指标 | 测试值 | SLA 门限 | 结果 |
|------|--------|---------|------|
| 请求成功率 | <replay_success_rate>% | ≥ 99% | ✅ / ❌ |
| TTFT P90 | <replay_ttft_p90_s>s | ≤ 1.5s | ✅ / ❌ |
| E2E P90 | <replay_e2e_p90_s>s | <模型特定门限> | ✅ / ❌ |

> 无回放数据时此节标注"未执行回放压测"。

### 4. QPS 拐点结论

| 配置 | SLA 合规最大 QPS | 拐点类型 |
|------|----------------|---------|
| TP=<tp_size>×1 实例 | <sla_max_qps> req/s | <inflection_type> |

**SLA 基准**：<sla_threshold>

> 多组对比（如 TP vs DP）：此处填最优配置结论，对比详情见实验数据索引。

### 5. 实验数据索引

| 实验目录 | 类型 | 关键结论 |
|---------|------|---------|
| `results/<dir>/` | 回放压测 | 成功率 <n>%，TTFT P90 <x>s |
| `results/<dir>/` | QPS 拐点扫描 | 拐点 <x> req/s |
| `results/<dir>/` | 多组对比 | <结论一句话> |
```

---

## Step 6：更新索引

在 `results/README.md` 的"快速导航"部分确认已有指向 `results/models/` 的链接，若无则添加：

```markdown
- 模型评估报告 → [`results/models/`](models/)
```

---

## 完成输出

```
【评估报告已生成 ✅】
  路径：results/models/<model-name>/EVAL_REPORT.md
  上线建议：✅ 可上线
  推荐规模：<N> 个实例 × <M> 张 <gpu_type>（共 <GPU总数> 卡）
```

---

## 验证状态

| 模型 | 状态 |
|------|------|
| tianji-querysafety-4b-v2-3 | ✅ 已验证（2026-03-16，model-context.md + 5 份实验产物，EVAL_REPORT.md 生成完整）|
