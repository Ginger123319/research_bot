# 评估结果索引

> 模型部署迁移评估实验结果归档目录  
> 更新：2026-03-23

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
| ~~xinghan-guoxue-72b-v1-2-reason_qps_sweep_20260316~~ *(已归档，V1 兜底数据)* | guoxue-72b-reason | QPS 拐点扫描 | ⚠️ 数据已作废，见 [archive/guoxue-v1-deprecated/](archive/guoxue-v1-deprecated/ARCHIVED.md) | 2026-03-16 |
| ~~guoxue_qps_sweep_20260317~~ *(已归档，V1 兜底数据)* | guoxue-72b-reason | QPS 拐点扫描（完整版）| ⚠️ 数据已作废，见 archive/guoxue-v1-deprecated/ | 2026-03-17 |
| ~~guoxue_qps_peak_finder_20260318~~ *(已归档，V1 兜底数据)* | guoxue-72b-reason | qps-peak-finder（Phase1+2+3）| ⚠️ 数据已作废，见 archive/guoxue-v1-deprecated/ | 2026-03-18 |
| [guoxue-v2-8tp-peak-finder-20260323](#guoxue-v2-8tp-peak-finder-20260323) | guoxue-72b-reason | qps-peak-finder（8×L20，V2 真实数据）| ideal_rps=0.2114 req/s（12.7 RPM），SLA E2E≤180s ✅ | 2026-03-23 |
| [guoxue-v2-h20-peak-finder-20260323](#guoxue-v2-h20-peak-finder-20260323) | guoxue-72b-reason | qps-peak-finder（4×H20，V2 真实数据）| ideal_rps=0.5878 req/s（35.3 RPM），SLA E2E≤180s ✅ | 2026-03-23 |
| [guoxue-v2-h20-vs-l20-peak-finder-20260323](#guoxue-v2-h20-vs-l20-peak-finder-20260323) | guoxue-72b-reason | H20 vs L20 综合对比（✅ 最终结论参考）| 4×H20 以 0.5× GPU 实现 2.78× QPS，推荐 9实例×4H20=36卡 | 2026-03-23 |
| [guoxue-v2-eagle3-8l20-peak-finder-20260323](#guoxue-v2-eagle3-8l20-peak-finder-20260323) | guoxue-72b-reason | qps-peak-finder（Eagle3 8×L20，推测解码加速）| ideal_rps=0.3169 req/s（19.0 RPM），SLA E2E≤180s ✅，比 vanilla 8×L20 提升 **1.50×** | 2026-03-23 |
| [guoxue-v2-eagle3-4h20-probe-20260324](#guoxue-v2-eagle3-4h20-probe-20260324) | guoxue-72b-reason | Eagle3 4×H20 rps=0.5878 探针 | ❌ 三项 SLA 失败（E2E P90=480.5s），系统过载，max sustainable RPS ≈ 0.548 req/s | 2026-03-24 |
| [guoxue-v2-mixed-replay-20260323](#guoxue-v2-mixed-replay-20260323) | guoxue-72b-reason | 迁移验证回放（6×4H20+4×8L20，256 RPM）| ✅ 成功率 99.89%，E2E P90=100.7s，SLA 全通过 | 2026-03-23 |
| [guoxue-v2-4h20-9l20-replay-20260323](#guoxue-v2-4h20-9l20-replay-20260323) | guoxue-72b-reason | 迁移验证回放（4×4H20+9×8L20，256 RPM）| ✅ 成功率 99.89%，E2E P90=115.5s，SLA 全通过 | 2026-03-23 |
| [tianji-querysafety_peak_finder_20260319](#tianji-querysafety_peak_finder_20260319) | tianji-querysafety-4b-v2-3 | qps-peak-finder（bakv1 新版）| ⚠️ 生产档验证✅，8实例余量仅2.6%，建议扩9实例 | 2026-03-19 |
| [ziwei-32b_peak_finder_20260319](#ziwei-32b_peak_finder_20260319) | ziwei-32b-v1 | qps-peak-finder（8TP 复验）| ❌ 生产 100RPM > SLA上限 95.4RPM，建议扩至 2×8TP | 2026-03-19 |
| [lingyu_qps_sweep_20260317](#lingyu_qps_sweep_20260317) | lingyu-235b-A22b-v9 | QPS 拐点扫描 | 软拐点 2.0 req/s，全档 SLA 通过至 3.0 req/s，无回放测试 | 2026-03-17 |
| [chart-32b-8tp_qps_20260318](#chart-32b-8tp_qps_20260318) *(已归档)* | chart-32b-agent | QPS 拐点扫描（8TP，早期）| 已被 peak-finder 替代 | 2026-03-18 |
| [chart-32b-4tp_qps_20260318](#chart-32b-4tp_qps_20260318) *(已归档)* | chart-32b-agent | QPS 拐点扫描（4TP，早期）| 已被 peak-finder 替代 | 2026-03-18 |
| [chart-32b_peak_finder_20260319](#chart-32b_peak_finder_20260319) | chart-32b-agent | qps-peak-finder（8TP vs 4TP，Phase1+2+3）| ⚠️ V1 数据存疑，已被 V2 替代 | 2026-03-19 |
| [chart-32b_replay_20260320](#chart-32b_replay_20260320) | chart-32b-agent | 峰值回放（118 RPM，3实例×8TP）| ⚠️ 成功率 99.19%，TTFT P90=0.135s，E2E P90=6.81s，QPS容量11×余量 | 2026-03-20 |
| [**chart_agent_tp_compare_20260325**](#chart_agent_tp_compare_20260325) | chart-32b-agent | **qps-peak-finder V2（Agent数据集，8TP vs 4TP）✅ 最终结论** | **8TP ideal 3.83 req/s（230 RPM）/ 4TP ideal 2.22 req/s（133 RPM），8TP/4TP=1.73×** | **2026-03-25** |
| [**chart_agent_8tp_replay_20260326**](#chart_agent_8tp_replay_20260326) | chart-32b-agent | **生产峰值回放（Agent V2 数据，118 RPM，单实例 8TP）✅** | **成功率 100%，TTFT P90=0.207s，TTFS P90=0.518s，E2E P90=14.0s，SLA 全部大幅达标** | **2026-03-26** |
| [guoxue-v2-4h20-probe-infra-base-20260325](#guoxue-v2-4h20-probe-infra-base-20260325) | guoxue-72b-reason | Vanilla H20 infra-base 探针（rps=0.5878）| ⚠️ 成功率 100%，TTFT/TTFS 达标，E2E P90=189.6s 略超 SLA（共享负载影响）| 2026-03-25 |
| [guoxue-v2-eagle3-4h20-probe-infra-opti-20260325](#guoxue-v2-eagle3-4h20-probe-infra-opti-20260325) | guoxue-72b-reason | Eagle3 infra-opti 探针（rps=0.5878）| ❌ 成功率 75.15%，E2E P90=600.6s，系统过载二次确认，max sustainable RPS ≈ 0.52 req/s | 2026-03-25 |

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

---

### ~~xinghan-guoxue-72b-v1-2-reason_qps_sweep_20260316~~ *(已归档，V1 兜底数据)*

> ⚠️ **已移入 `archive/guoxue-v1-deprecated/`**，数据来自 V1 兜底数据集（system prompt 不对，business_peak_rpm 口径错误），所有结论**不可用于上线决策**。

---

### ~~guoxue_qps_sweep_20260317~~ *(已归档，V1 兜底数据)*

> ⚠️ **已移入 `archive/guoxue-v1-deprecated/`**，数据来自 V1 兜底数据集（business_peak_rpm 仅 43 RPM，漏统 MCP 213 RPM）。所有结论**不可用**，V2 正式评估见下方。

---

### guoxue-v2-8tp-peak-finder-20260323

**模型**：`xinghan-guoxue-72b-v1-2-reason`（72B 八字国学长推理）  
**类型**：qps-peak-finder 三阶段（**8×L20，V2 真实数据**）  
**数据集**：`output_guoxue_v2` poisson_256，真实线上 system prompt，avg_output_len=1386 tokens  
**SLA 基准**：TTFS P90 ≤ 1.5s，E2E P90 ≤ 180s（业务确认），成功率 ≥ 99%

**关键结论**：
- ideal_rps = **0.2114 req/s（12.7 RPM）**，bracket [0.2114, 0.2235] 宽 5.4%
- 极限 RPS = 0.2498 req/s（Phase 2 首档实测，发生陡崖型崩溃）
- Phase 3 全部 4 档 SLA ✅，E2E P90 ≤ 153.5s

**主要文件**：
- `REPORT.md` — 完整三阶段报告
- `plot_*.html` — 交互式延迟/吞吐曲线

---

### guoxue-v2-h20-peak-finder-20260323

**模型**：`xinghan-guoxue-72b-v1-2-reason`（72B 八字国学长推理）  
**类型**：qps-peak-finder 三阶段（**4×H20，V2 真实数据**）  
**数据集**：同 8×L20 组（V2 poisson_256），avg_output_len=2157 tokens（H20 实测）  
**说明**：Phase 3 首次（2026-03-22）因服务崩溃数据污染，2026-03-23 重跑后全档通过

**关键结论**：
- ideal_rps = **0.5878 req/s（35.3 RPM）**，bracket [0.5878, 0.6044] 宽 2.82%
- 极限 RPS = 0.7348 req/s，服务端承载并发 ≈ 46（Little's Law）
- Phase 3 全部 4 档 SLA ✅，E2E P90 ≤ 114.9s（裕量 36%）
- **4×H20 以 0.5× GPU 实现 2.78× 的 QPS 承载**，延迟也更优（E2E -25%，TTFS -28%）

**主要文件**：
- `REPORT.md` — 完整三阶段报告（含 8×L20 vs 4×H20 对比）
- `qps0.5878_analysis_REPORT.md` — 理想 RPS 档单点深度分析（含 Grafana 监控横向比对）
- `qps0.5878_analysis.html` — 交互式 CDF 报告（TTFT/TTFS/E2E/ITL）
- `plot_*.html` — 交互式延迟/吞吐曲线

---

### guoxue-v2-h20-vs-l20-peak-finder-20260323

**模型**：`xinghan-guoxue-72b-v1-2-reason`  
**类型**：4×H20 vs 8×L20 综合对比（✅ **最终上线决策参考**）

**核心对比**：

| 指标 | 8×L20 | 4×H20 | H20/L20 |
|------|-------|-------|:---:|
| ideal_rps | 0.2114 req/s | **0.5878 req/s** | **2.78×** |
| E2E P90（ideal档）| 153.5s | **114.8s** | ↓ 25% |
| 满足 256 RPM 需 GPU 数 | 168 卡 | **32 卡** | **0.19×** |
| 单卡效率 | 1.59 RPM/卡 | **8.83 RPM/卡** | **5.56×** |

**上线建议**：优先 **9 实例 × 4×H20 = 36 卡**（承载 317.7 RPM，余量 24%）

**主要文件**：
- `REPORT.md` — 综合对比报告（含容量规划、运维建议）
- `plot_*.html` — 两组容量曲线对比图

---

### lingyu_qps_sweep_20260317

**模型**：`lingyu-235b-A22b-v9-2`（Qwen3-235B-A22B，MoE 通用对话）  
**类型**：QPS 拐点扫描（远端 k8s 平台，8TP 部署）  
**数据集**：21 档（1.0~3.0 req/s，步长 0.1）  
**⚠️ 注意**：QPS sweep 完成，**未做回放测试**（H20 环境限制）  
**结论**：
- 软拐点：**QPS = 2.0 → 2.1 req/s**（TTFS P90 跳变 +34%）
- SLA 上限：**3.0 req/s**（全档成功率 100%，TTFS P90 最高 1.387s < 1.5s）
- 推荐生产配置：单实例 ≤ 2.0 req/s（120 RPM），7 实例覆盖 800 RPM 峰值
- 拐点类型：**软拐点**（排队累积，GPU 未饱和，延迟增长可控）

**主要文件**：
- `REPORT.md` — QPS 拐点报告（含 21 档数值、资源规划建议）
- `plot_*.html` — 交互式 QPS/延迟/吞吐图

---

### chart-32b-8tp_qps_20260318

**模型**：`xinghan-chart-32b-v1-1-agent`（32B 星盘普通场景，8TP 部署）  
**类型**：🔄 QPS 拐点扫描（**进行中**）  
**数据集**：`xinghan-chart-32b-v1-1-agent_all.csv`（6,016 条有效直接调用记录）  
**扫描配置**：20 档（2.0~4.0 req/s，每档 25min，冷却 90s）  
**预计完成**：2026-03-19 凌晨  
**日志目录**：`logs/chart-32b-8tp/qps_20260318_134151/`  
**⚠️ 数据说明**：原始索引 47,338 条中仅 6,016 条（12.7%）有完整 prompt（详见 `clingo/docs/ai_data/xinghan-chart-32b-v1-1-agent-data-structure.md`）

**主要文件**（完成后更新）：
- `REPORT.md` — QPS 拐点报告

---

### chart-32b-4tp_qps_20260318

**模型**：`xinghan-chart-32b-v1-1-agent`（32B 星盘普通场景，4TP 对照部署）  
**类型**：🔄 QPS 拐点扫描（**进行中**）  
**数据集**：同 8TP 组（`xinghan-chart-32b-v1-1-agent_all.csv`，6,016 条）  
**扫描配置**：20 档（2.0~4.0 req/s，每档 25min，冷却 90s）  
**预计完成**：2026-03-19 凌晨  
**日志目录**：`logs/chart-32b-4tp/qps_20260318_134345/`  
**目的**：与 8TP 做承载能力对比（同一模型不同 TP 并行度）

**主要文件**（完成后更新）：
- `REPORT.md` — QPS 对照报告

---

### guoxue-v2-mixed-replay-20260323

**类型**：迁移验证回放压测  
**模型**：`xinghan-guoxue-72b-v1-2-reason`  
**部署**：6×4×H20 + 4×8×L20（统一入口，共 10 实例）  
**时间**：2026-03-23 14:56 → 15:49（约 53 分钟）

**测试参数**：
- 数据集：`poisson_256_stitched.csv`（6,358 条，40 分钟时间跨度，真实流量 Poisson 插值 256 RPM）
- 模式：`--keep-income-time`（按原始 income_time 时间戳回放）

**核心结果**：

| 指标 | 值 | SLA | 判断 |
|------|-----|-----|------|
| 成功率 | 99.89% | ≥ 99% | ✅ |
| TTFT P90 | 0.989 s | ≤ 1.5s | ✅ 余量 34% |
| TTFS P90 | 1.139 s | ≤ 1.5s | ✅ 余量 24% |
| E2E P90 | 100.7 s | ≤ 180s | ✅ 余量 44% |
| E2E P99 | 121.2 s | — | ✅ |

**结论**：✅ SLA 全部通过，当前混合部署可支撑 256 RPM 业务峰值。总理论承载 262.6 RPM，余量仅 2.6%，建议设置 250 RPM Grafana 预警阈值。

**文件**：
- `REPORT.md` — 完整迁移验证报告
- `guoxue-mixed-10inst_replay_256rpm_analysis.html` — 交互式分析图表
- `*.png` — 7 张静态图表（TTFT/TTFS/E2E CDF + 并发时间线 + 成功率时间线）

---

### guoxue-v2-4h20-9l20-replay-20260323

**类型**：迁移验证回放压测（新部署方案）  
**模型**：`xinghan-guoxue-72b-v1-2-reason`  
**部署**：4×4×H20 + 9×8×L20（统一入口，共 13 实例）  
**时间**：2026-03-23 17:26 → 18:20（约 54 分钟）

**背景**：从 6H20+4L20 调整为 4H20+9L20，释放 2 台 H20（8 卡）用于实验，按 1H20≈5L20 补入 5 台 8xL20。

**测试参数**：
- 数据集：`poisson_256_stitched.csv`（6,358 条，40 分钟时间跨度，复用基线数据集）
- 模式：`--keep-income-time`（按原始 income_time 时间戳回放）

**核心结果**：

| 指标 | 值 | SLA | 判断 |
|------|-----|-----|------|
| 成功率 | 99.89% | ≥ 99% | ✅ |
| TTFT P90 | 1.029 s | ≤ 1.5s | ✅ 余量 31% |
| TTFS P90 | 1.182 s | ≤ 1.5s | ✅ 余量 21% |
| E2E P90 | 115.5 s | ≤ 180s | ✅ 余量 36% |
| E2E P99 | 148.8 s | — | ✅ |

**与基线方案（6H20+4L20）对比**：延迟小幅升高（E2E P90 +14.7%），成功率完全一致，SLA 全部通过。

**结论**：✅ SLA 全部通过，4×4H20+9×8L20 部署可支撑 256 RPM 峰值，三月当前峰值（约 195 RPM）余量 +31%。

**文件**：
- `REPORT.md` — 完整迁移验证报告（含与 6H20+4L20 横向对比）
- `guoxue-4h20-9l20_replay_256rpm_analysis.html` — 交互式分析图表
- `*.png` — 7 张静态图表

---

### guoxue-v2-eagle3-4h20-probe-20260324

**模型**：`xinghan-guoxue-72b-v1-2-reason`（72B 八字国学长推理）  
**类型**：Eagle3 4×H20 单点探针（rps=0.5878，对标 Vanilla H20 理想 RPS）  
**数据集**：`xinghan-guoxue-72b-v1-2-reason_all.csv`（50K 条完整日志）  
**测试时间**：2026-03-24

**关键结论**：
- **❌ 全面 SLA 失败**：E2E P90=480.5s（SLA ≤180s），TTFS P90=2.197s，成功率 98.87%
- **根因**：Eagle3 4×H20 最大可持续 RPS ≈ **0.548 req/s**（decode 1224 tok/s ÷ avg 2232 tok），低于测试 RPS 0.5878（超载 7.2%）
- 系统过载证据：Grafana 并发全程单调上升 19→265，从未达稳态
- Eagle3 spec_accept_length=2.66（正常），但 decode 吞吐（1224 tok/s）反而低于 Vanilla（1260 tok/s）
- **Eagle3 4×H20 vs Vanilla 4×H20（同 RPS）**：E2E P90 差 318%（480.5s vs 114.9s）

**主要文件**：
- `REPORT.md` — 探针分析报告（含根因分析、Grafana 监控、与 Vanilla 对比）
- `eagle3_4h20_probe_rps0.5878_analysis.html` — 交互式 CDF 报告

---

### guoxue-v2-eagle3-8l20-peak-finder-20260323

**模型**：`xinghan-guoxue-72b-v1-2-reason`（72B 八字国学长推理）  
**类型**：qps-peak-finder 三阶段（**Eagle3 推测解码，8×L20，V2 真实数据**）  
**数据集**：`output_guoxue_v2` poisson_256，avg_output_len=2172 tokens（Eagle3 实测；比 vanilla 多 57%）  
**SLA 基准**：TTFS P90 ≤ 1.5s，E2E P90 ≤ 180s，成功率 ≥ 99%

**关键结论**：
- ideal_rps = **0.3169 req/s（19.0 RPM）**，bracket [0.3169, 0.3246] 宽 2.43%
- 极限 RPS = **0.3486 req/s（Phase 2 首档实测 FAIL）**
- 服务端承载并发 ≈ **37**（Little's Law：0.2641 × 142.9s）
- Phase 3 全部 4 档 SLA ✅，E2E P90 ≤ 172.1s
- **Eagle3 vs vanilla 8×L20**：ideal_rps 从 0.2114 提升至 0.3169，增幅 **+50%**
- ⚠️ Phase 2 第一次运行因测试污染无效（TTFS P90=124s），第二次冷却后重跑正常收敛

**主要文件**：
- `REPORT.md` — 完整三阶段报告（含 Little's Law、决策路径、E3 vs vanilla 对比）
- `plot_latency_2d.html` / `plot_qps.html` / `plot_throughput.html` — 交互式容量曲线

---

### tianji-querysafety_peak_finder_20260319

**模型**：`tianji-querysafety-4b-v2-3`（安全拦截分类模型，4TP bakv1）  
**方法**：qps-peak-finder 三阶段（Phase 1 + Phase 2 完成，Phase 3 进行中）  
**部署**：4TP×1实例（L20 GPU × 4），线上 8 实例  

**关键结论**：
- ideal_rps = **7.8554 req/s（471 RPM/实例）**，Phase 2 bracket [7.8554, 8.0609] 宽 2.5%
- 极限 RPS = 52.59 req/s，server 承载并发 ≈ 18（Little's Law）
- Phase 3 生产档 7.47 req/s 验证：✅ E2E P90 = 268ms，SLA 合规
- ⚠️ **8 实例余量仅 2.6%**（容量 3677 RPM vs 生产峰值 3584 RPM），建议扩至 **9 实例（余量 14%）**
- Phase 3 剩余 2 档（qps7.7269 + qps7.8554）后台运行中，图表待更新

**报告**：`results/tianji-querysafety_peak_finder_20260319/REPORT.md`

---

### ziwei-32b_peak_finder_20260319

**模型**：`xinghan-ziwei-32b-v1`（32B 对话模型，8TP 复验）  
**方法**：qps-peak-finder 三阶段  
**部署**：8TP×1实例（L20 GPU × 8）

**关键结论**：
- ideal_rps = **1.5902 req/s**（95.4 RPM），bracket [1.5902, 1.6179] 宽 1.7%
- 极限 RPS = 2.09 req/s，server 峰值承载并发 ≈ 60（Little's Law）
- ❌ **生产 100 RPM（1.667 req/s）> SLA 上限 95.4 RPM**，峰值 TTFS P90 = 1783ms，超限 19%
- 历史网格搜索（1.50 req/s）vs peak-finder（1.5902 req/s）：精度提升 +6%，结论一致
- 建议：**2×8TP 实例**（16 卡 L20，联合承载 ~191 RPM，有 91% 余量）

**报告**：`results/ziwei-32b_peak_finder_20260319/REPORT.md`

---

### chart-32b_peak_finder_20260319

**模型**：`xinghan-chart-32b-v1-1-agent`（32B 星盘普通场景）  
**方法**：qps-peak-finder 三阶段（Phase1 饱和探测 / Phase2 自适应逼近 / Phase3 验证网格）  
**部署对比**：8TP×1实例 vs 4TP×1实例（L20 GPU）  
**数据集**：`xinghan-chart-32b-v1-1-agent_full.csv`

**关键结论**：
- 8TP ideal_rps = **7.61 req/s**（457 RPM），极限 RPS = 7.37 req/s，server并发极限 ≈ 272
- 4TP ideal_rps = **4.19 req/s**（252 RPM），极限 RPS = 4.98 req/s，server并发极限 ≈ 247
- 8TP/4TP 承载比 = **1.82×**（GPU 2×，效率 91%）
- SLA 拐点均由 TTFS P90 触发（prefill侧）；E2E P90 距上限 5.5× 裕量
- 生产峰值 118 RPM，**单 4TP 实例即可覆盖（213% 裕量）**
- ⚠️ Agent 框架调用（41,320条）未纳入测试，建议补充回放验证

**报告**：`results/chart-32b_peak_finder_20260319/REPORT.md`  
**图表**：`results/chart-32b_peak_finder_20260319/plot_latency_2d.html`

---

---

### chart-32b_replay_20260320

**模型**：`xinghan-chart-32b-v1-1-agent`（星盘占星 Agent 调用）  
**实验类型**：峰值回放验证（118 RPM，3 实例 × 8TP × L20）  
**测试时间**：2026-03-20 14:52 → 16:43（约 110 分钟）

**关键结论**：
- 成功率：**99.19%**（5,826 请求，47 条失败，主为超时；宽松标准通过，严格 99.9% 略低）
- TTFT P90：**0.135 s**（SLA ≤ 1.5s，余量 91%）
- TTFS P90：**0.442 s**（SLA ≤ 1.5s，余量 71%）
- E2E P90：**6.811 s**（SLA ≤ 150s，余量充足）
- 单实例均摊 ~39 RPM，**QPS 容量 11× 余量**（距 ideal_rps 457 RPM 极宽裕）
- ⚠️ indexed 格式数据需先分片+建 3 列索引 _all.csv 才能使用 DataSampler（已记录 SKILL.md）

**报告**：`results/chart-32b_replay_20260320/REPORT.md`  
**分析图**：`results/chart-32b_replay_20260320/chart-32b-8tp_replay_118rpm_analysis.html`

---

### guoxue-v2-4h20-probe-infra-base-20260325

**模型**：`xinghan-guoxue-72b-v1-2-reason`（Vanilla 4×H20 TP4，infra-base 端点）
**实验类型**：生产端点 rps=0.5878 探针验证
**测试时间**：2026-03-25 11:40 — 12:42（≈62 分钟）

**关键结论**：
- 成功率：**100.00%** ✅
- TTFT P90：**0.565s** ✅（SLA ≤1.5s）
- TTFS P90：**0.752s** ✅（SLA ≤1.5s）
- E2E P90：**189.55s** ⚠️（SLA ≤180s，略超 5%，因共享负载并发偏高至 83.6，直连基线 114.9s）
- Grafana 并发均值：83.58，TTFT P90：0.60s，服务稳态无崩溃

**报告**：`results/guoxue-v2-4h20-probe-infra-base-20260325/REPORT.md`
**分析图**：`results/guoxue-v2-4h20-probe-infra-base-20260325/probe_rps0.5878_analysis.html`

---

### guoxue-v2-eagle3-4h20-probe-infra-opti-20260325

**模型**：`xinghan-guoxue-72b-v1-2-reason`（Eagle3 4×H20 TP4，infra-opti 端点）
**实验类型**：Eagle3 生产端点 rps=0.5878 探针（二次确认）
**测试时间**：2026-03-25 11:56 — 13:01（≈65 分钟）

**关键结论**：
- 成功率：**75.15%** ❌（526 超时失败）
- TTFT P90：**1.420s** ⚠️ 临界
- TTFS P90：**3.315s** ❌（SLA ≤1.5s）
- E2E P90：**600.59s** ❌（触及超时上限，SLA ≤180s）
- Grafana 并发均值 256.66 / 峰值 338，系统严重过载
- 估算 max sustainable RPS ≈ **0.52 req/s**（测试速率 0.5878 超出约 11.5%）
- 与 2026-03-24 测试结论一致，属**二次确认过载**

**报告**：`results/guoxue-v2-eagle3-4h20-probe-infra-opti-20260325/REPORT.md`
**分析图**：`results/guoxue-v2-eagle3-4h20-probe-infra-opti-20260325/probe_rps0.5878_analysis.html`

---

### chart_agent_tp_compare_20260325

**模型**：`xinghan-chart-32b-v1-1-agent`（Agent 模式，/mnt/ai-llm/chartv5）  
**实验类型**：QPS Peak Finder V2（8TP vs 4TP，Agent 全量数据集，✅ **最终结论**）  
**测试时间**：2026-03-25 15:41 — 2026-03-26 01:00（约 9.5 小时）

**背景**：V1 数据存疑（与线上监控偏差）。V2 使用重建的 Agent 全量数据集（840,336 条）重新执行完整 Peak Finder 三阶段。

**关键结论（V2）**：

| 配置 | 理想 RPS | 理想 RPM | TTFS P90@SLA边界 | 8TP/4TP倍率 |
|------|---------|---------|----------------|-----------|
| 4TP（infra-opti） | **2.2175 req/s** | **133 RPM** | 1,488 ms（裕量 0.8%）| — |
| 8TP（infra） | **3.8286 req/s** | **230 RPM** | 1,443 ms（裕量 3.8%）| **1.73×** |

- 生产负载（118 RPM）下：4TP TTFS P90=1415ms（裕量约 5.7%），8TP TTFS P90=790ms（裕量 47%）
- V2 vs V1 QPS 下降：Agent 模式输出含工具调用序列，avg_output_len ~475 tok（V1 为纯对话数据）
- **上线建议**：当前 4TP 可运行但裕量极小；业务增长超 133 RPM 需升级 8TP

**报告**：`results/chart_agent_tp_compare_20260325/REPORT.md`  
**图表**：`results/chart_agent_tp_compare_20260325/plot_latency_2d.html`

---

### chart_agent_8tp_replay_20260326

**模型**：`xinghan-chart-32b-v1-1-agent`（Agent 模式，单实例 8TP）  
**实验类型**：生产峰值回放压测（Agent V2 数据集，118 RPM）  
**测试时间**：2026-03-26 12:25 ～ 14:06（≈ 100 分钟）

**背景**：在 QPS Peak Finder V2 确认 8TP SLA 上限为 230 RPM 后，使用真实 Agent 调用数据（含动态生成的占星 system prompt，平均 2,689 字符）在生产当前峰值 118 RPM 下做回放验证。旧 V1 回放（2026-03-20）使用直接调用数据（system prompt 仅 360 字符），存在严重偏差，本次为修正版。

**数据构建**：取 5 天（2026-03-11~15）凌晨峰值窗口（00:00~00:20），共 1,518 行，拼接后 99.4 分钟，泊松插值至 118 RPM，输出 5,779 条。

**关键结论**：

| 指标 | 实测值 | SLA 阈值 | 结论 |
|------|--------|---------|------|
| 成功率 | **100.00%** | ≥ 99% | ✅ |
| TTFT P90 | **0.207 s** | ≤ 1.5 s（裕量 86%）| ✅ |
| TTFS P90 | **0.518 s** | ≤ 1.5 s（裕量 65%）| ✅ |
| E2E P90 | **14.034 s** | ≤ 150.0 s（裕量 91%）| ✅ |

8TP 在 118 RPM（SLA 上限 230 RPM 的 51%）下延迟裕量充足，可以安全承载当前及短期内业务增长。

**报告**：`results/chart_agent_8tp_replay_20260326/REPORT.md`

---

## 快速导航

- **模型评估索引（openclaw 入口）** → [`results/models/INDEX.yaml`](models/INDEX.yaml)
- 模型评估报告 → [`results/models/`](models/)
- 已跑通模型清单 → [`clingo/docs/README.md`](../clingo/docs/README.md)
- 新模型接入 SOP → [`clingo/docs/workflow/model-onboarding.md`](../clingo/docs/workflow/model-onboarding.md)
- Skill 体系 → [`clingo/docs/planning/skills-roadmap.md`](../clingo/docs/planning/skills-roadmap.md)
