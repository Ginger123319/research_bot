# 评估结果索引

> 模型部署迁移评估实验结果归档目录  
> 更新：2026-03-13

每个子目录对应一组实验，包含：交互式可视化 HTML（`plot_*.html`）或离线分析图（`*.png`）、量化分析报告（`REPORT.md`）。

---

## 目录总览

| 子目录 | 模型 | 实验类型 | 关键结论 | 日期 |
|--------|------|---------|---------|------|
| [ziwei_benchmark_20260310_163524](#ziwei_benchmark_20260310_163524) | ziwei-32b | 回放压测 | ✅ 生产峰值压力下稳定，满足上线预期 | 2026-03-10 |
| [ziwei_tp_compare_20260310](#ziwei_tp_compare_20260310) | ziwei-32b | TP8 vs TP4 对比 | TP8 拐点 1.50 req/s，TP4 拐点 0.92 req/s，TP8 约 1.63× | 2026-03-10 |
| [hepan_benchmark_20260312](#hepan_benchmark_20260312) | hepan-72b | 回放压测 | ✅ 150 RPM（~2× 峰值）成功率 99.95%，可上线 | 2026-03-12 |
| [hepan_qps_jyf_20260312](#hepan_qps_jyf_20260312) | hepan-72b | QPS 拐点扫描 | 拐点 0.70 req/s（严格）/ 0.80 req/s（宽松）| 2026-03-12 |
| [hepan_qps_compare_data600_20260312](#hepan_qps_compare_data600_20260312) | hepan-72b | 数据集对比 | 两组数据集拐点均 0.80 req/s，性能基本一致 | 2026-03-12 |
| [tianji_querysafety_benchmark_20260312](#tianji_querysafety_benchmark_20260312) | tianji-querysafety-4b | 回放压测 | ✅ 真实峰值成功率 100%，可正常上线 | 2026-03-12 |
| [tianji_querysafety_4tp_qps_20260311](#tianji_querysafety_4tp_qps_20260311) | tianji-querysafety-4b | QPS 扫描（低段）| 4TP 低段（QPS 4.0~6.79）基线数据 | 2026-03-11 |
| [tianji_querysafety_4tp_fullrange_20260313](#tianji_querysafety_4tp_fullrange_20260313) | tianji-querysafety-4b | QPS 拐点（全范围）| 4TP 拐点 8.0~8.5 req/s（480 RPM），E2E P95 首超标 | 2026-03-13 |
| [tianji_querysafety_4tp_vs_4dp_20260313](#tianji_querysafety_4tp_vs_4dp_20260313) | tianji-querysafety-4b | 4TP vs 4DP 对比（含异常点）| 含 KV Cache 异常档位的原始对比 | 2026-03-13 |
| [tianji_querysafety_4tp_vs_4dp_filtered_20260313](#tianji_querysafety_4tp_vs_4dp_filtered_20260313) | tianji-querysafety-4b | 4TP vs 4DP 对比（剔除异常）| ✅ 最终结论：4TP 拐点 8.0 req/s，4DP 全档 FAIL | 2026-03-13 |

---

## 详细说明

### ziwei_benchmark_20260310_163524

**模型**：`xinghan-ziwei-32b-v1`（32B 通用对话）  
**类型**：回放压测  
**数据集**：`poisson_100` 插值，3,036 条，~60 min  
**结论**：✅ 新部署服务在生产峰值压力下表现稳定，TTFT / E2E 与线上 Grafana 监控趋势吻合，满足上线预期

**主要文件**：
- `REPORT.md` — 完整压测报告
- `ziwei_replay_100rpm_offline_analysis.html` — 交互式离线分析
- `benchmark-data-poisson_100_compare.png` — 泊松插值 vs 原始流量对比图

---

### ziwei_tp_compare_20260310

**模型**：`xinghan-ziwei-32b-v1`  
**类型**：TP8 vs TP4 QPS 承载能力对比  
**结论**：
- TP8：最大合规 QPS = **1.50 req/s**（≈ 90 RPM，TTFS P90 ≤ 1.5s）
- TP4：最大合规 QPS = **0.92 req/s**（≈ 55 RPM）
- TP8 承载能力约为 TP4 的 **1.63×**

**主要文件**：
- `REPORT.md` — 对比报告
- `plot_qps.html` / `plot_throughput.html` / `plot_latency_2d.html` — 交互式对比图

---

### hepan_benchmark_20260312

**模型**：`xinghan-hepan-72b-v1-2`（72B 通用对话，占星/合盘场景）  
**类型**：回放压测（150 RPM，~2× 线上峰值）  
**数据集**：`poisson_150` 插值，6,034 条，~66 min  
**结论**：✅ 成功率 **99.95%**，TTFT P90 = 1.147s，E2E P90 = 13.4s，功能输出质量正常，服务具备上线条件

**主要文件**：
- `REPORT.md` — 完整压测报告
- `REPORT_hepan_replay_180rpm.md` — 附加 180 RPM 档位报告
- `hepan_peak_replay_150rpm_analysis.html` — 交互式离线分析
- `xinghan-hepan-72b-v1-2_grafana_peak_*.png` — Grafana 线上监控截图

---

### hepan_qps_jyf_20260312

**模型**：`xinghan-hepan-72b-v1-2`  
**类型**：QPS 拐点扫描（原始业务数据集）  
**结论**：
- 严格 SLA（TTFS P90 ≤ 1.5s）：拐点 **0.70 req/s**（≈ 42 RPM）
- 宽松 SLA（TTFS P90 ≤ 1.6s）：拐点 **0.80 req/s**（≈ 48 RPM）

**主要文件**：
- `REPORT.md` — QPS 拐点报告
- `plot_*.html` — 三维交互图（QPS / Throughput / Latency）

---

### hepan_qps_compare_data600_20260312

**模型**：`xinghan-hepan-72b-v1-2`  
**类型**：数据集差异对比（原始 vs data600 截断集）  
**结论**：两组数据集在宽松 SLA 下最大合规 QPS 均为 **0.80 req/s**，data600 TTFS P90 略低约 3~4%，性能基本一致，数据集长度分布对结果影响有限

**主要文件**：
- `REPORT.md` — 对比分析报告
- `plot_*.html` — 双组交互式对比图

---

### tianji_querysafety_benchmark_20260312

**模型**：`tianji-querysafety-4b-v2-3`（4B 内容安全审核模型）  
**类型**：回放压测  
**数据集**：`_peak30min.csv` 直接回放，44,099 条，~30 min  
**结论**：✅ 成功率 **100%**，TTFT / E2E 表现优异，可正常上线  
**说明**：输出为 `{"label": "...", "instruction": "..."}` 格式 JSON，属于安全拦截类模型

**主要文件**：
- `REPORT.md` — 完整压测报告
- `tianji_querysafety_peak_replay_1422rpm_analysis.html` — 交互式离线分析
- `tianji-querysafety-4b-v2-3_grafana_peak_*.png` — Grafana 监控截图

---

### tianji_querysafety_4tp_qps_20260311

**模型**：`tianji-querysafety-4b-v2-3`（4TP 部署）  
**类型**：QPS 扫描，低段基线数据（QPS 4.0~6.79，45 min/档）  
**说明**：此目录为分段扫描的低段数据，完整全范围分析见 `tianji_querysafety_4tp_fullrange_20260313`

**主要文件**：
- `REPORT.md` — 低段报告
- `plot_*.html` — 交互式图

---

### tianji_querysafety_4tp_fullrange_20260313

**模型**：`tianji-querysafety-4b-v2-3`（4TP 部署）  
**类型**：QPS 拐点扫描，全范围（34 档，已剔除 QPS=6.90/7.00 KV Cache 异常点）  
**数据来源**：低段 `logs/tianji_4tp_qps_merged_filtered`（28档）+ 高段 `logs/tianji_4tp_highqps_20260313_121446`（6档）合并  
**结论**：
- 拐点：**QPS 8.0 → 8.5 req/s**（E2E P95 在 8.5 档首次超标 0.422s > 0.400s）
- 业务峰值 2168 RPM（36.1 req/s）覆盖需 **6 个 4TP 实例 = 24 卡 H100**（含 20% 余量）

**主要文件**：
- `REPORT.md` — 全范围拐点分析报告（含扩容建议）
- `plot_*.html` — 34 档交互式图

---

### tianji_querysafety_4tp_vs_4dp_20260313

**模型**：`tianji-querysafety-4b-v2-3`  
**类型**：4TP vs 4DP 初版对比（含 KV Cache 异常档位）  
**说明**：此目录包含异常档位（QPS=6.90/7.00 等），为历史中间结果，最终结论请参考 `tianji_querysafety_4tp_vs_4dp_filtered_20260313`

**主要文件**：
- `REPORT.md` — 初版对比报告（含异常点）

---

### tianji_querysafety_4tp_vs_4dp_filtered_20260313

**模型**：`tianji-querysafety-4b-v2-3`  
**类型**：4TP vs 4DP 最终对比（已剔除异常档位，✅ 最终推荐参考）  
**结论**：
| 配置 | SLA 合规最大 QPS | 说明 |
|------|----------------|------|
| **4TP × 1实例** | **8.0 req/s** | ✅ 全 36 档 PASS |
| **1TP × 4DP** | 无 | ❌ 全 28 档 FAIL，E2E P90 超标 4~8× |

**根本原因**：8K Token system prompt prefill 是瓶颈，4TP 将注意力头分摊到 4 块 GPU，延迟约为 1TP 的 1/4  
**部署建议**：tianji-querysafety 应优先使用 **4TP** 而非 4DP

**主要文件**：
- `REPORT.md` — 最终对比分析报告（含根因分析与部署建议）
- `plot_*.html` — 两组交互式对比图

---

## 快速导航

- 已跑通模型清单 → [`clingo/docs/README.md`](../clingo/docs/README.md)
- 新模型接入 SOP → [`clingo/docs/workflow/model-onboarding.md`](../clingo/docs/workflow/model-onboarding.md)
- Skill 体系 → [`clingo/docs/skills/skills-roadmap.md`](../clingo/docs/skills/skills-roadmap.md)
