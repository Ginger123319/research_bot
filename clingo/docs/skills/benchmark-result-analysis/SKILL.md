# Skill: benchmark-result-analysis

## 概述

对 LLM 回放/QPS 压测结束后，从原始结果 CSV 生成：

1. **交互式 HTML 报告**（完整图表，供本地查看）
2. **静态 PNG 图表**（供 REPORT.md 引用，无需截图）
3. **REPORT.md 骨架**（预填数字 + 图片引用 + Grafana 截图提示，补充文字后即为完整报告）

工具链：`scripts/analysis/offline_analysis.py`（基于 `single_exp.analysis_response()`，无需启动 Dash 服务）

---

## 前置条件

- benchmark 已完成，结果 CSV 位于 `logs/<model-full-name>/<exp_dir>/<exp_name>.csv`
- Python venv：`.venv/bin/python`（已含 plotly、matplotlib、pandas、numpy）

---

## 步骤

### Step 1 — 确认结果 CSV 路径

```bash
# 找到最新一次实验的 CSV（<model-full-name> = 算法提供的完整模型名）
ls logs/<model-full-name>/<exp_dir>/
# 通常命名为 <exp_name>.csv，例如：
# logs/xinghan-ziwei-32b-v1-1/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv
```

### Step 2 — 运行离线分析脚本

```bash
cd /mnt/ai-infra/users/wnd/workspace/execute/guofan

.venv/bin/python scripts/analysis/offline_analysis.py \
  --csv  logs/<model-full-name>/<exp_dir>/<exp_name>.csv \
  --out  results/<report_dir>/<exp_name>_analysis.html \
  --png-dir   results/<report_dir> \
  --model-name "<model-name>"
```

**参数说明：**

| 参数 | 说明 | 示例 |
|------|------|------|
| `--csv` | benchmark 结果 CSV | `logs/xinghan-ziwei-32b-v1-1/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv` |
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
| TTFS | Time To First **Sentence** | 首句完整返回耗时（= TTFT + 首句 decode 时间）|
| ITL | Inter-Token Latency | per-token 间隔时间（`tpot` 字段），555K+ 条/次实验 |
| User-TPOT | User-perceived TPOT | 每请求平均 TPOT = `(end−first_token) / completion_tokens` |
| E2E | End-to-End latency | 从发送到最后一个 token 的总时间 |

> **ITL vs User-TPOT 区别：**
> - ITL：token 粒度，能看单次 decode step 抖动（P99 通常比均值高很多）
> - User-TPOT：请求粒度，均值平滑后结果，用于整体 SLA 评估

### ⚠️ TTFS 常见误解（必读）

| 误解 | 正确理解 |
|------|---------|
| TTFS = "Time to First Stream"（首字节） | ❌ 错误：TTFS = "Time to First **Sentence**"（首句） |
| TTFS ≈ TTFT（值相近或相等） | ❌ 错误：TTFS > TTFT，差值为首句 decode 时间（通常 0.x～数秒）|
| 直接从 CSV 列读取 TTFS | ❌ 错误：原始 CSV **没有** `ttfs` 列，必须通过 `analysis_response()` 解析 `token_list` 计算 |
| 任何中间件/ad-hoc 脚本计算 TTFS | ⚠️ 风险：需确认其通过 `token_list` 找到中文标点（`。！？，：`）来定位首句边界 |

**如果看到对比报告中 TTFS 数值 = TTFT 数值，说明 TTFS 计算有误，需要重新通过标准脚本生成。**

---

## 多 CSV 横向对比（新场景）

当需要对比多个版本/配置的 benchmark 结果时，**必须使用 `compare_analysis.py`**，不能直接读 CSV 列做对比。

### 使用场景
- 不同 SGLang 版本对比（如 0.4.6 vs 0.5.5）
- 不同 TP/DP 配置对比
- 不同 benchmark 参数对比

### 命令

```bash
cd /mnt/ai-infra/users/wnd/workspace/execute/guofan

# 两个 CSV 对比
.venv/bin/python scripts/analysis/compare_analysis.py \
  --csv logs/<model-full-name>/exp_a/result_a.csv logs/<model-full-name>/exp_b/result_b.csv \
  --names "版本A" "版本B" \
  --out results/compare_20260318/compare_report.md \
  --html results/compare_20260318/compare_report.html

# 三个 CSV 对比（以第 0 个为基准）
.venv/bin/python scripts/analysis/compare_analysis.py \
  --csv logs/a.csv logs/b.csv logs/c.csv \
  --names "0.4.6-r08" "0.4.6+2params-r08" "0.5.5-r08" \
  --base 0 \
  --out results/compare_report.md
```

### 输出

脚本终端打印并生成 Markdown 报告，包含：
- 成功率 / QPS / 总耗时
- TTFT / TTFS / E2E 的 Mean + P50/P90/P95/P99（正确计算）
- 各指标相对基准的变化百分比
- 可选 HTML CDF 叠加对比图

> ⚠️ **为什么不能直接读 CSV 列？**
> 原始 CSV 只有 `token_list`（原始 JSON），没有预计算的 `ttft`/`ttfs` 列。
> `compare_analysis.py` 内部调用 `analysis_response()` → `analysis_row()` 来：
> - 从 `token_list[0]["timestamp"]` 和 `token_list[1]["timestamp"]` 计算 TTFT
> - 扫描 `token_list` 中第一个含 `。！？，：` 的 token 计算 TTFS

---

## 常见问题

| 问题 | 原因 | 处理 |
|------|------|------|
| `load_exp_csv` 返回 error | CSV 格式不符合 benchmark 工具输出规范 | 检查 CSV 是否来自 `benchmark` 命令的 output-dir |
| PNG 中文标题显示为方块 | 系统无 CJK 字体 | 已改为全英文标签，无需处理 |
| 骨架中仍出现 `<见图>` | `offline_analysis.py` 版本过旧，未包含分位数计算 | 确认使用最新版脚本（2026-03-16 后），P50/P90/P95/P99 已自动填入 |
| TTFS = TTFT（对比报告数值相同） | 使用了 ad-hoc 脚本直接读 CSV，未通过 `analysis_response()` 计算 | 改用 `compare_analysis.py` 重新运行 |
| TTFS 被标注为 "Time to First Stream" | 模型误解了缩写含义 | TTFS = Time to First **Sentence**（首句），提醒 AI 重新计算 |

---

## 示例：ziwei 回放测试

```bash
.venv/bin/python scripts/analysis/offline_analysis.py \
  --csv  logs/xinghan-ziwei-32b-v1-1/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv \
  --out  results/ziwei_benchmark_20260310_163524/ziwei_replay_100rpm_analysis.html \
  --png-dir   results/ziwei_benchmark_20260310_163524 \
  --model-name "xinghan-ziwei-32b-v1"
```

完成后补充 REPORT.md 中的背景和论证段落，添加 Grafana 截图，即完成完整的迁移验证报告。

---

## 分析完成后的归档动作（强制）

每次分析完成后，**必须**执行以下归档动作：

### 1. 更新实验目录 README.md 结果指针

在 `logs/<exp_dir>/README.md` 的"快速结论"区补填真实数值：

```markdown
## 快速结论
- 成功率：<N>%（从 REPORT.md 填入）
- TTFT P90：<x>s
- E2E P90：<x>s

## 结果指针
- 分析报告 → results/<report_dir>/REPORT.md  ← 填入真实路径
```

### 2. 更新 `results/README.md`

在 `results/README.md` 的目录总览表中补充本次实验条目：

```markdown
| [<report_dir>](#<report_dir>) | <model> | 回放压测 | ✅ 成功率 <N>%，TTFT P90 <x>s | YYYY-MM-DD |
```

并在详细说明节追加对应的完整描述段落。

### 3. model-context.md 追加

```yaml
replay_success_rate: <N>
replay_ttft_p90_s: <x>
replay_ttfs_p90_s: <x>
replay_e2e_p90_s: <x>
```

### 4. results/models/INDEX.yaml 追加回放指标

在对应模型的 `performance:` 节追加回放字段（**不覆盖已有字段**）：

```yaml
# 找到模型条目，在 performance 下追加：
performance:
  replay_success_rate: <N>        # 百分比，保留两位小数
  replay_ttft_p90_s: <x>         # 秒
  replay_e2e_p90_s: <x>          # 秒
```

> 仅回放分析完成后写入；无回放测试时跳过此步，INDEX.yaml 中不添加这些字段。
