# hepan-72b-v1 QPS 承载能力分析报告

> **测试时间**：2026-03-12  
> **测试目标服务**：`https://infer.geniuworks.com/infra-xinghan-hepan-p72b-v1/v1/chat/completions`  
> **结论**：在严格 SLA 基准（TTFS P90 ≤ 1.5s）下，最大合规 QPS 为 **0.70 req/s（≈ 42 RPM）**；在宽松基准（TTFS P90 ≤ 1.6s）下，最大合规 QPS 为 **0.80 req/s（≈ 48 RPM）**。QPS=0.80 档位 TTFS P90 = 1.577s，接近但不超过 1.6s，拐点在 QPS=0.80~0.90 之间。

---

## 一、测试配置

| 参数 | 值 |
|------|-----|
| 模型 | `xinghan-hepan-p72b-v1` |
| 数据集 | `xinghan-hepan-72b-v1-2_selected_0302-235503_0303-001503_poisson_180.csv` |
| 请求模式 | `--request-rate`（均匀 QPS 施压）|
| KV Cache | `--no-kvcache`（禁用缓存，避免延迟虚低）|
| `max_completion_tokens` | 4096 |
| 每档时长 | 600 秒（10 分钟）|
| 扫描范围 | QPS 0.6 → 1.1，共 6 档 |

---

## 二、逐档 SLA 明细

| QPS (req/s) | TTFS P90 (s) | E2E P90 (s) | 成功率 | SLA 判定 |
|-------------|-------------|------------|--------|---------|
| 0.60 | 1.280 | 16.5 | 100.0% | ✅ PASS |
| **0.70** | **1.340** | **17.1** | **100.0%** | **✅ PASS** |
| 0.80 | 1.578 ⚠️ | 18.8 | 100.0% | ❌ FAIL |
| 0.90 | 1.782 | 21.8 | 100.0% | ❌ FAIL |
| 1.00 | 2.003 | 26.5 | 100.0% | ❌ FAIL |
| 1.10 | 2.287 | 30.0 | 100.0% | ❌ FAIL |

**SLA 基准**：TTFS P90 ≤ 1.5s | E2E P90 ≤ 150s | 成功率 ≥ 99%

---

## 三、拐点分析

### 3.1 拐点位置

**拐点在 QPS = 0.80 req/s**：

- QPS 0.70 → 0.80，TTFS P90 从 1.340s 跳升至 1.578s（+17.8%），越过 1.5s 基准线
- QPS 0.80 → 1.10 持续线性恶化，每 +0.10 QPS，TTFS P90 约增加 0.24s

### 3.2 瓶颈分析

| 维度 | 表现 | 结论 |
|------|------|------|
| TTFS P90 | QPS=0.80 起超标，随 QPS 线性增长 | **prefill 是瓶颈**，GPU 算力不足以在 1.5s 内完成高并发 prefill |
| E2E P90 | 最高仅 30s（QPS=1.10），远低于 150s | decode 侧余量充足，无 decode 侧瓶颈 |
| 成功率 | 全程 100%，未见任何请求失败 | 服务稳定，未进入过载状态 |

### 3.3 与 ziwei-32b 的横向对比参考

| 模型 | 最大合规 QPS | 拐点指标 | 备注 |
|------|-------------|---------|------|
| ziwei-32b TP8 | 1.50 req/s | TTFS P90 @ QPS=1.60 | 8 GPU TP |
| ziwei-32b TP4 | 0.92 req/s | TTFS P90 @ QPS=0.94 | 4 GPU TP |
| **hepan-72b TP?** | **0.70 req/s** | **TTFS P90 @ QPS=0.80** | 待确认 GPU 配置 |

> hepan-72b 参数量（72B）约为 ziwei-32b（32B）的 2.25x，在相近 GPU 配置下 QPS 承载更低符合预期。

---

## 四、结论与建议

### 4.1 承载能力结论

**在当前部署配置下，hepan-72b-v1 的 SLA 合规最大 QPS 为 0.70 req/s（≈ 42 RPM）**。

- 若业务侧峰值 RPM ≤ 42，当前部署可满足上线 SLA 要求
- 若峰值 RPM 在 42~48（对应 0.70~0.80 QPS）之间，属于灰色区域，需进一步精查 0.70~0.80 之间的档位

### 4.2 建议

1. **补充 0.72 / 0.74 / 0.76 / 0.78 档位扫描**（如需精确定位拐点到 0.02 步精度）
2. **确认当前 GPU 配置**（TP 数量），以便与 ziwei-32b 做归一化对比
3. **比对线上 Grafana 监控**的实际峰值 RPM，评估当前部署是否满足业务需求

---

## 五、附录

### 5.1 文件清单

| 文件 | 说明 |
|------|------|
| `plot_qps.html` | Success QPS 随输入 QPS 变化曲线 |
| `plot_throughput.html` | prefill / decode / overall 吞吐趋势 |
| `plot_latency_2d.html` | ttft / e2e / tpot 等 P50/P90/P99 延迟对比 |
| `REPORT.md` | 本报告 |

### 5.2 原始数据来源

```
/mnt/ai-infra/users/shared/llm-benchmark-web/llm-benchmark-web-data/workspaces/jyf/results/
  hepan_rps_test_request-rate_0_6.csv  (QPS=0.6)
  hepan_rps_test_request-rate_0_7.csv  (QPS=0.7)
  hepan_rps_test_request-rate_0_8.csv  (QPS=0.8)
  hepan_rps_test_request-rate_0_9.csv  (QPS=0.9)
  hepan_rps_test_request-rate_1.csv    (QPS=1.0)
  hepan_rps_test_request-rate_1_1.csv  (QPS=1.1)
```

---

*报告生成时间：2026-03-12*  
*分析工具：`multi_exp_compare.py` + `qps-sweep-comparison` Skill*
