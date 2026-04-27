# Dashboard 极限场景指标展示设计

**日期**：2026-03-19  
**状态**：已实施  
**相关文件**：`scripts/serve.py`、`results/models/INDEX.yaml`

---

## 背景与目标

当前 Dashboard（http://172.21.208.11:18999/）模型卡片只展示 SLA 合规拐点（`sla_max_qps_rps`），不包含服务在最大吞吐场景下的能力信息。

**目标**：在每个模型卡片中新增「极限场景」可折叠区块，展示服务在硬件吞吐上限下的：
- 极限 RPS（`saturation_rps`）
- 极限 RPM（`saturation_rpm`）
- 可容并发数（`saturation_concurrency`）

辅助工程师在**容量规划和服务启动配置**时了解服务的绝对上限。

---

## 数据来源

| 字段 | 来源 | 说明 |
|------|------|------|
| `saturation_rps` | qps-peak-finder Phase 1 `max_rps_estimate` | 硬件极限吞吐，忽略 SLA |
| `saturation_rpm` | `saturation_rps × 60` | 换算为分钟请求数 |
| `saturation_concurrency` | Phase 1 峰值并发（`peak_decode_throughput` 对应的 `con=N`） | 服务可同时承载的最大请求数 |

**覆盖范围**：仅限跑过 qps-peak-finder Phase 1 饱和测试的模型。当前已有数据的模型：

| 模型 | saturation_rps | saturation_concurrency |
|------|----------------|------------------------|
| xinghan-guoxue-72b-v1-2-reason | 0.371 req/s | 120 |

其他模型（tianji / ziwei / hepan / lingyu）使用普通 QPS sweep，无 Phase 1 数据，展示 N/A，后续补测时再填充。

---

## INDEX.yaml 数据模型扩展

在 `performance` 块下新增三个可选字段：

```yaml
performance:
  # 原有字段（不变）
  sla_max_qps_rps: 0.2494
  sla_max_qps_rpm: 14.96
  sla_criterion: "..."
  replay_success_rate: null
  replay_ttft_p90_s: null
  replay_e2e_p90_s: null
  # 新增：Phase 1 饱和测试产出（可选，无数据留 null）
  saturation_rps: 0.371          # max_rps_estimate，硬件吞吐上限（req/s）
  saturation_rpm: 22.3           # saturation_rps × 60
  saturation_concurrency: 120    # 峰值并发数（Phase 1 最优 con 档位）
```

字段均为**可选**，null 时 Dashboard 不显示极限区块。

---

## Dashboard 展示设计

### 展示位置
在模型卡片的「查看报告」按钮**下方**，实验列表**上方**插入可折叠区块。

### 折叠实现
使用原生 HTML `<details><summary>` 标签，零 JS 依赖，兼容所有浏览器。

### 视觉样式
- 使用浅黄背景（`#fff8c5`）+ 橙色边框，与 SLA 合规区（白色）视觉区分
- 标注「⚠️ 硬件上限，超出 SLA」警示，避免误用

### 展示内容示例（展开后）

```
▶ 极限场景（Phase 1 饱和测试）

极限 RPS：0.371 req/s（22.3 RPM）
可容并发：120
⚠️ 以上为硬件吞吐上限，已超出 SLA，仅供容量规划参考
```

---

## serve.py 改动说明

1. `_PERFORMANCE_KEYS` 增加 `saturation_rps`、`saturation_rpm`、`saturation_concurrency`
2. `_render_model_card()` 末尾：若 `saturation_rps` 有值，渲染 `<details>` 折叠块；否则跳过
3. `_CSS` 增加 `.saturation-block` 样式类

---

## 决策记录

| 问题 | 决策 | 理由 |
|------|------|------|
| 无 Phase 1 数据的模型怎么办 | 留 null，不显示区块 | 避免用不准确的 sweep 最高点误导 |
| 是否展示极限点的 P90 E2E / TTFS | 不展示 | Phase 1 用 max-concurrency 模式测吞吐，无 P90 延迟 |
| 折叠还是直接展示 | 默认折叠 | SLA 拐点是主要信息，极限参数是补充参考 |
