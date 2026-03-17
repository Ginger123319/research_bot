# Skill: benchmark-result-analysis

## 概述

对 LLM 回放/QPS 压测结束后，从原始结果 CSV 生成：

1. **交互式 HTML 报告**（完整图表，供本地查看）
2. **静态 PNG 图表**（供 REPORT.md 引用，无需截图）
3. **REPORT.md 骨架**（预填数字 + 图片引用 + Grafana 截图提示，补充文字后即为完整报告）

工具链：`scripts/analysis/offline_analysis.py`（基于 `single_exp.analysis_response()`，无需启动 Dash 服务）

---

## 前置条件

- benchmark 已完成，结果 CSV 位于 `logs/<exp_dir>/<exp_name>.csv`
- Python venv：`.venv/bin/python`（已含 plotly、matplotlib、pandas、numpy）

---

## 步骤

### Step 1 — 确认结果 CSV 路径

```bash
# 找到最新一次实验的 CSV
ls logs/<exp_dir>/
# 通常命名为 <exp_name>.csv，例如：
# logs/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv
```

### Step 2 — 运行离线分析脚本

```bash
cd /mnt/ai-infra/users/wnd/workspace/execute/guofan

.venv/bin/python scripts/analysis/offline_analysis.py \
  --csv  logs/<exp_dir>/<exp_name>.csv \
  --out  results/<report_dir>/<exp_name>_analysis.html \
  --png-dir   results/<report_dir> \
  --model-name "<model-name>"
```

**参数说明：**

| 参数 | 说明 | 示例 |
|------|------|------|
| `--csv` | benchmark 结果 CSV | `logs/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv` |
| `--out` | HTML 报告输出路径 | `results/ziwei_benchmark_20260310_163524/analysis.html` |
| `--png-dir` | PNG 导出目录（省略则跳过 PNG）| `results/ziwei_benchmark_20260310_163524` |
| `--model-name` | 模型名，填入骨架标题 | `xinghan-ziwei-32b-v1` |

### Step 3 — 检查输出

脚本完成后在 `--png-dir` 下生成以下文件：

| 文件 | 内容 |
|------|------|
| `ttft_cdf.png` | TTFT 累积分布（含 P50/P90/P99/P100/Mean 标注）|
| `ttfs_cdf.png` | TTFS 累积分布 |
| `user_tpot_cdf.png` | User-TPOT 累积分布（请求粒度）|
| `itl_cdf.png` | ITL 累积分布（per-token TPOT，降采样）|
| `e2e_cdf.png` | E2E 累积分布 |
| `concurrency_timeline.png` | 活跃请求数 / RPS / CPS 时间线 |
| `success_rate_timeline.png` | 请求成功率时间线（60s 滑动窗口）|

同时终端打印 **REPORT.md 骨架**，包含：
- 所有量化数据（成功率、QPS、吞吐量）
- **TTFT / TTFS / E2E 的 P50/P90/P95/P99 真实数值**（已自动计算，无需手动读图）
- 图片引用 + Grafana 截图提示

### Step 4 — 获取 Grafana 截图（手动）

> **Grafana 监控面板地址：**
> `http://172.21.52.62:3000/d/cb7f886a-289f-4052-ae50-913644582b64/geniuworks`
>
> 建议截取内容：
> - TTFT / E2E / RPM 面板
> - 时间范围：对齐本次测试的开始/结束时间
>
> 保存为 `results/<report_dir>/grafana_snapshot.png`

### Step 5 — 填写 REPORT.md

将终端打印的骨架复制到 `results/<report_dir>/REPORT.md`，**对照 `clingo/docs/workflow/reporting-template.md` 中的模板 A（回放压测报告）逐节填写**：

- **§一 背景与目的**：迁移/上线背景、测试目标
- **§二 2.1 数据构建流程**：参考 traffic-dataset-prep Skill 描述
- **§三 3.2 延迟分位数**：**骨架已预填 P50/P90/P95/P99 真实数值，直接复制即可，无需手动读图**
- **§四 有效性论证**：数据真实性（3 段固定结构）、流量充分性、与 Grafana 比对
- **§五 结论与上线建议**：业务判断，SLA 达标表必须含判断标准列

> ⚠️ **延迟表填写规范**：REPORT.md 的延迟分布表必须包含具体数值（`offline_analysis.py` 已自动生成），**不允许留 `<见图>` 占位符**——`<见图>` 会导致 `model-context.md` 和 `EVAL_REPORT.md` 无法自动读取 P90 数据。
>
> 📋 **完整写作规范**：`clingo/docs/workflow/reporting-template.md`（含模板A回放报告 + 模板B QPS拐点报告 + 通用必填字段规则）

---

## HTML vs PNG vs REPORT.md 定位

| 产物 | 定位 | 用途 |
|------|------|------|
| HTML | 客观结果可视化（交互式）| 本地查看完整图表，供自己和 AI 分析 |
| PNG | 静态图表截图替代品 | 嵌入 REPORT.md，归档 |
| REPORT.md | 完整测试叙述文档 | 串联数据→测试→结果→结论，对外交付 |

---

## 指标说明

| 指标 | 全称 | 语义 |
|------|------|------|
| TTFT | Time To First Token | 首个 token 返回耗时（Prefill 延迟代理）|
| TTFS | Time To First Sentence | 首句完整返回耗时（= TTFT + 首句 decode 时间）|
| ITL | Inter-Token Latency | per-token 间隔时间（`tpot` 字段），555K+ 条/次实验 |
| User-TPOT | User-perceived TPOT | 每请求平均 TPOT = `(end−first_token) / completion_tokens` |
| E2E | End-to-End latency | 从发送到最后一个 token 的总时间 |

> **ITL vs User-TPOT 区别：**
> - ITL：token 粒度，能看单次 decode step 抖动（P99 通常比均值高很多）
> - User-TPOT：请求粒度，均值平滑后结果，用于整体 SLA 评估

---

## 常见问题

| 问题 | 原因 | 处理 |
|------|------|------|
| `load_exp_csv` 返回 error | CSV 格式不符合 benchmark 工具输出规范 | 检查 CSV 是否来自 `benchmark` 命令的 output-dir |
| PNG 中文标题显示为方块 | 系统无 CJK 字体 | 已改为全英文标签，无需处理 |
| 骨架中仍出现 `<见图>` | `offline_analysis.py` 版本过旧，未包含分位数计算 | 确认使用最新版脚本（2026-03-16 后），P50/P90/P95/P99 已自动填入 |

---

## 示例：ziwei 回放测试

```bash
.venv/bin/python scripts/analysis/offline_analysis.py \
  --csv  logs/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv \
  --out  results/ziwei_benchmark_20260310_163524/ziwei_replay_100rpm_analysis.html \
  --png-dir   results/ziwei_benchmark_20260310_163524 \
  --model-name "xinghan-ziwei-32b-v1"
```

完成后补充 REPORT.md 中的背景和论证段落，添加 Grafana 截图，即完成完整的迁移验证报告。
