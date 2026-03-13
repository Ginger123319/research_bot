---
name: llm-replay-benchmark
description: Use when verifying a deployed LLM service can handle amplified peak traffic at realistic traffic shape — replaying Poisson-interpolated datasets with keep-income-time to simulate burst/quiet patterns and validate service quality at a target RPM.
---

# LLM Replay Benchmark

## Overview

按数据集中的原始时间戳（`income_time`）回放请求，模拟真实流量的**突发 + 低谷交替形态**。

**核心用途**：JSONL 日志实测 RPM 通常低于监控平台统计峰值，通过泊松插值放大后做回放，验证服务在预期峰值负载下的稳定性（成功率 / 延迟是否符合 SLA）。

**与 QPS 扫描的区别**：

| | 回放（本 Skill）| QPS 扫描 |
|--|---|---|
| 速率控制 | `income_time` 决定（真实流量形态）| `--request-rate` 固定 QPS |
| 用途 | 验证目标 RPM 下服务质量 | 找服务承载上限/拐点 |
| 数据 | `_poisson_{RPM}_stitched.csv` | `_all.csv` 或峰值文件 |
| 运行次数 | 通常 1~2 次（不同 RPM 档位）| 多档循环（15~60 档）|
| 时长 | 由数据时间跨度决定（~60min）| 每档固定时长 × 档位数 |

---

## 数据选择

使用 `traffic-dataset-prep` 步骤4 泊松插值产出的文件：

```
{MODEL}_selected_combined_Ndays_peak_poisson_{TARGET_RPM}_stitched.csv
```

**TARGET_RPM 选择原则**：设为业务预期承载的峰值负载（如监控平台统计最高峰值），而非 JSONL 实测值（通常偏低）。

```
JSONL 实测 RPM: 16      ← 数据来源，真实形态
监控平台峰值:   29      ← 更接近实际
压测目标 RPM:   100     ← 设定服务需承载的极限，验证此档位
```

---

## 核心调用

直接调 `benchmark` CLI，**不经 `example_llm_benchmark_test.sh` 包装**：

```bash
VENV="/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/bin"
OUTDIR="logs/${MODEL_NAME}_peak_replay_$(date +%Y%m%d_%H%M%S)"

"${VENV}/benchmark" \
  --exp-name "${MODEL_NAME}_peak_replay_${TARGET_RPM}rpm" \
  --dataset-path "datas/output/${DATASET_FILE}" \
  --url "${SERVER_URL}" \
  --tokenizer "${TOKENIZER_PATH}" \
  --keep-income-time \
  --no-kvcache \
  --max-completion-tokens ${MAX_TOKENS} \
  --output-dir "${OUTDIR}" \
  2>&1 | tee "logs/${MODEL_NAME}_replay_$(date +%Y%m%d_%H%M%S).log"
```

**关键参数说明**：

| 参数 | 值 | 说明 |
|------|-----|------|
| `--keep-income-time` | 必填 | 按 income_time 列时间戳发送，不设速率 |
| `--no-kvcache` | 必填 | 每请求加 UUID 前缀，防 KV 缓存命中 |
| `--max-completion-tokens` | 对话 4096 / 短输出 256 | 按模型输出类型设置 |
| `--request-rate` | **不设置** | 速率由数据控制 |
| `--num-requests` | **不设置** | 全量跑完数据集 |

---

## 实验命名约定

```
exp-name:   {MODEL_NAME}_peak_replay_{TARGET_RPM}rpm
输出目录:   logs/{MODEL_NAME}_peak_replay_{TIMESTAMP}/
日志文件:   logs/{MODEL_NAME}_replay_{TIMESTAMP}.log
```

---

## 输出结构

回放完成后，`${OUTDIR}/` 下生成 2 个文件（无子目录）：

```
{MODEL}_peak_replay_{RPM}rpm.csv       ← 每条请求的详细结果
{MODEL}_peak_replay_{RPM}rpm.argv.csv  ← 完整参数记录
```

日志通过 `tee` 同时打印到终端和独立 `.log` 文件。

---

## 执行时长

由数据集时间跨度决定，无法预先设置：

```
poisson_100_stitched.csv（3036 条，~60min 时间窗口）→ 回放耗时 ~60min
```

运行期间查看进度：
```bash
tail -f logs/{MODEL}_replay_<timestamp>.log
```

---

## 分析结果

```bash
analysis --host 0.0.0.0 --port 8050 --exp logs/{MODEL}_peak_replay_{TIMESTAMP}
```

**成功判断标准**（同 QPS 扫描）：

| 指标 | 通过标准 |
|------|---------|
| 成功率 | ≥ 99% |
| TTFT P90 | 与单请求基线相比无明显抬升 |
| POST 异常 | 0（偶发 1~2 可接受）|

---

## 与 QPS 扫描的配合使用

```
回放（目标 RPM）→ 验证服务质量是否符合预期
      │
      ├─ 通过：服务可承载目标 RPM，质量稳定
      │
      └─ 不通过：用 QPS 扫描找实际拐点，确定最大稳定 QPS
```

---

## 常见错误

| 错误 | 根因 | 修复 |
|------|------|------|
| 回放速率远低于预期 RPM | `income_time` 列时区偏移 8h 导致请求间隔被拉长 | 检查 `income_time` 是否已做 `tz_localize(None)` |
| 所有请求瞬间发出（无间隔）| 未加 `--keep-income-time` | 确认参数存在 |
| 结果 CSV 只有 argv 文件 | exp-name 与已有文件重名，自动加 `_01` 后缀 | 正常行为，结果在 `{exp}_01.csv` |
| `income_time_delta` 列缺失 | `--keep-income-time` 未生效 | 确认参数拼写，检查 benchmark 版本 |

---

**参考实验**：`logs/ziwei_peak_replay_20260310_135418`（poisson_29）、`logs/ziwei_peak_replay_20260310_163524`（poisson_100，3036 条，~60min）
