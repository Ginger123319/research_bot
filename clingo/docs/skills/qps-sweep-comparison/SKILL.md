---
name: qps-sweep-comparison
description: Use when QPS sweep benchmarks have finished and you need to visualize results, evaluate SLA compliance (TTFS P90, E2E P90, model-specific thresholds), find the inflection point for a single deployment, or compare capacity curves across multiple deployment groups (e.g. TP8 vs TP4).
---

# QPS Sweep Comparison

## Overview

对已完成的 QPS 扫描结果做**可视化 + SLA 评估 + 报告生成**。
支持**单组**（找拐点/SLA 合规上限）或**多组**（对比不同部署配置的承载能力差异）。
与 `qps-benchmark-sweep`（执行层）完全解耦——只需结果目录，不依赖运行中的 benchmark 进程。

| Skill | 场景 |
|-------|------|
| `benchmark-result-analysis` | 单次回放/压测的离线分析（offline_analysis.py）|
| `qps-sweep-comparison` | QPS 扫描结果可视化 + SLA 评估 + 报告（本 Skill）|

---

## 前置条件

- QPS 扫描已完成，结果在 `logs/<exp_dir>/` 下
- 每个子目录（一个档位）含 `*.csv` + `*.argv.csv` 两个文件
- Python 解释器：`/mnt/ai-infra/users/wnd/workspace/execute/guofan/.venv/bin/python3`

---

## Step 1 — 配置（三种方式，推荐优先级从高到低）

### 方式 A（推荐）：YAML 配置文件（不修改脚本）

在项目任意目录下创建 YAML 文件，然后用 `--config` 参数指定：

```yaml
# configs/tianji_4tp_fullrange.yaml
groups:
  - label: "4TP×1实例"
    dir: "/mnt/ai-infra/users/wnd/workspace/execute/guofan/logs/tianji_4tp_qps_merged"

x_key: request_rate
output_dir: "/mnt/ai-infra/users/wnd/workspace/execute/guofan/results/tianji_querysafety_4tp_fullrange_20260313"

sla_config:
  ttfs_p90: 1.5
  e2e_p90: 0.4
  success_rate: 0.99
  custom:
    - metric: e2e
      percentile: 95
      limit: 0.4
      label: "tianji E2E P95"
```

```bash
cd /mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark

/mnt/ai-infra/users/wnd/workspace/execute/guofan/.venv/bin/python3 \
    -m llm_benchmark.analysis.analysis.multi_exp_compare \
    --config /mnt/ai-infra/users/wnd/workspace/execute/guofan/configs/tianji_4tp_fullrange.yaml
```

优点：配置与脚本完全隔离，可版本管理，不会污染脚本底部默认值。

---

### 方式 B：修改脚本底部配置区（快速调试用）

工具路径：`third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/src/llm_benchmark/analysis/analysis/multi_exp_compare.py`

```python
# 单组示例（找拐点）
GROUPS = [
    {"label": "TP8", "dir": "logs/ziwei_8tp_qps_20260310_all"},
]

# 多组示例（对比部署配置）
GROUPS = [
    {"label": "TP8", "dir": "logs/ziwei_8tp_qps_20260310_all"},
    {"label": "TP4", "dir": "logs/ziwei_4tp_qps_20260310_all"},
]

X_KEY = "request_rate"           # 或 "max_concurrency"
OUTPUT_DIR = "results/ziwei_tp_compare_20260310"   # 自动创建

# SLA 配置（默认通用基准，模型特定时取消注释）
SLA_CONFIG = None
# SLA_CONFIG = {
#     "ttfs_p90": 1.5, "e2e_p90": 0.4, "success_rate": 0.99,
#     "custom": [
#         {"metric": "e2e", "percentile": 95, "limit": 0.4, "label": "tianji E2E P95"},
#     ],
# }
```

- `label`：图例名称，手动指定（不自动提取，灵活应对各种目录命名）
- `OUTPUT_DIR`：输出目录放到 `results/` 下，按 `{model}_{date}` 命名

```bash
cd /mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark
/mnt/ai-infra/users/wnd/workspace/execute/guofan/.venv/bin/python3 \
    -m llm_benchmark.analysis.analysis.multi_exp_compare
```

---

### 方式 C：Python inline（一次性，不修改任何文件）

```bash
/mnt/ai-infra/users/wnd/workspace/execute/guofan/.venv/bin/python3 -c "
import multiprocessing as mp; mp.set_start_method('spawn', force=True)
from llm_benchmark.analysis.analysis.multi_exp_compare import run_compare
run_compare(
    groups=[
        {'label': 'TP8', 'dir': '/path/to/8tp_logs'},
        {'label': 'TP4', 'dir': '/path/to/4tp_logs'},
    ],
    x_key='request_rate',
    output_dir='results/my_compare_20260312',
    sla_config={
        'ttfs_p90': 1.5, 'e2e_p90': 0.4, 'success_rate': 0.99,
        'custom': [{'metric': 'e2e', 'percentile': 95, 'limit': 0.4, 'label': 'tianji E2E P95'}],
    },
)
"
```

---

## 跨目录合并（多段扫描拼接为一组）

**场景**：同一部署分两次扫描（如低段 QPS 4~7、高段 QPS 7.5~10），需合并为一个连续曲线。

**方法**：用 `cp -rl`（硬链接，速度快、不占额外空间）建立合并目录：

```bash
MERGED="/path/to/logs/model_qps_merged"
mkdir -p "$MERGED"

# 链接第一段
for d in /path/to/logs/exp1/qps_*/; do
    cp -rl "$d" "$MERGED/$(basename $d)"
done

# 链接第二段
for d in /path/to/logs/exp2/qps_*/; do
    cp -rl "$d" "$MERGED/$(basename $d)"
done
```

> ⚠️ **不要用 `ln -sfn`（符号链接到目录）**：Python 的 `Path.glob("**/*.csv")` 默认不追踪指向目录的符号链接，会导致脚本找不到任何文件。`cp -rl` 建立的硬链接目录可被正常遍历。

脚本执行完成后自动输出：
1. 各组分档明细（TTFS P90 / E2E P90 / 成功率 / PASS-FAIL）
2. 各组满足 SLA 的最大 QPS 汇总
3. 三个 HTML 文件路径

**异常档位处理**：删除子目录后重跑，脚本自动跳过：

```bash
rm -rf logs/<exp_dir>/<qps_subdir>
```

---

## Step 3 — 查看 HTML 图表

```bash
cd results && /mnt/ai-infra/users/wnd/workspace/execute/guofan/.venv/bin/python3 -m http.server 8765
```

| 文件 | 内容 |
|------|------|
| `plot_qps.html` | Success QPS 随输入 QPS 变化曲线 |
| `plot_throughput.html` | prefill / decode / overall 吞吐对比 |
| `plot_latency_2d.html` | ttft / e2e / tpot / user_tpot / ttfs 的 P50/P90/P99 |

**Latency 图交互说明**：

1. 右上角下拉菜单 → 选「仅 ttft」等（按指标过滤）
2. 图例每条线**独立可点**（P50/P90/P99 互不联动）
3. 典型用法：选「仅 e2e」→ 点隐 P50 和 P99 → 只看两组 E2E P90 对比

| 下拉按钮 | 作用 |
|---------|------|
| 显示全部 | 所有组所有指标 |
| 仅 {metric} | 所有组的该指标 P50/P90/P99 |
| 仅 {group} | 该组所有指标 |
| E2E + TTFT | 常用组合，图表默认态 |

---

## Step 4 — SLA 评估

### 通用基准（所有模型）

| 指标 | 基准 | 说明 |
|------|------|------|
| TTFS P90 | ≤ 1500 ms | 首句延迟，用户感知最直接 |
| E2E P90 | ≤ 150 s | 完整响应时间上限 |
| 请求成功率 | ≥ 99% | 低于此视为超过拐点 |

### 模型特定基准（按需补充）

| 模型 | 指标 | 基准 |
|------|------|------|
| tianji（安全检测）| 整体时长 P95 | ≤ 400 ms |
| （新模型按需补充）| — | — |

### 拐点识别

```
正常区：成功率 ≥99%，TTFS/E2E P90 随 QPS 平稳增长
拐点信号：
  - 成功率跌破 99%
  - TTFT P90 出现非线性跳变（如 1.3x → 1.5x → 2x 快速抬升）
  - Success QPS 曲线斜率开始偏离 y=x 对角线
过载区：成功率持续下跌，延迟快速发散
```

多组对比时：同一 QPS 档位对比各组 P90 延迟和吞吐，判断哪种配置更优及各组拐点差异。

---

## Step 5 — 生成 REPORT.md（AI 辅助）

将 SLA 分析输出交给 AI，请求生成 `results/<subdir>/REPORT.md`：

```
请基于以下 SLA 分析结果，生成 results/<subdir>/REPORT.md，参考 benchmark-result-analysis Skill 的报告风格，包含：
- 测试背景（部署配置、对比目的）
- 各组 SLA 合规最大 QPS 汇总表
- 拐点分析与原因
- 多组对比结论（若有）
- 上线/配置选择建议

[粘贴脚本输出的 SLA 分析表]
```

REPORT.md 放入 `results/<subdir>/`，与 HTML 文件同目录。

---

## 常见问题

| 问题 | 原因 | 处理 |
|------|------|------|
| 某组只有部分档位 | 子目录缺 `*.argv.csv` | 检查 sweep 脚本是否完整写入参数文件 |
| 两组 label 相同 | 文件名相同但 label 未区分 | 确认 GROUPS 中 label 手动设置正确 |
| Latency 图某条线缺失 | 该档位该指标数据为空 | 正常，脚本自动跳过 |
| SLA 判断与预期不符 | 使用了默认通用基准 | 按模型设置 SLA_CONFIG.custom |

---

## 示例：ziwei TP8 vs TP4 对比（2026-03-10）

```bash
# 脚本底部已配置，直接运行
cd .../llm-benchmark
.venv/bin/python3 -m llm_benchmark.analysis.analysis.multi_exp_compare

# 结果
# TP8: 满足 SLA 的最大 QPS = 1.50 req/s（TTFS 拐点在 QPS=1.60）
# TP4: 满足 SLA 的最大 QPS = 0.92 req/s（TTFS 拐点在 QPS=0.94）
# 主要瓶颈：TTFS P90（prefill 侧），E2E 未触达上限
# TP8 承载能力约为 TP4 的 1.63x（GPU 资源 2x，效率略低于线性）
```
