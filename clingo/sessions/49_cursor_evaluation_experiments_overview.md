# 我先在机器上进行的评估 试验有哪些？
_Exported on 2026/3/20 at GMT+8 17:57:38 from Cursor (transcript)_

---

**User**

我先在机器上进行的评估 试验有哪些？

---

**Cursor**

The user is asking about what evaluation experiments have been conducted on the machine. Let me look at the progress.md file and project_status.md to understand what has been done.

---

**Cursor**

根据 `project_status.md` 和 `progress.md`，以下是目前在机器上进行过的所有评估实验：

---

## 已完成评估实验汇总

### 1. xinghan-ziwei-32b-v1（紫微 32B）
- **QPS Sweep**：4TP + 8TP 双路，QPS 0.46~2.00，共 34 档（4TP）/ 30 档（8TP）
- **回放测试**：150 RPM 峰值回放
- **qps-peak-finder**（复验）：Phase 1 饱和探测 → Phase 2 自适应收敛（2026-03-19）
  - 饱和档位：con=70，max_rps = 2.0935 req/s
  - Phase 2 进行中，ideal_rps 预计 1.46~1.57 req/s

### 2. xinghan-guoxue-72b-v1-2-reason（国学 72B）
- **QPS Sweep**：8TP，24 档（0.190~0.350 req/s），每档 60 分钟，共 ~25h
  - 拐点：0.245 → 0.255 req/s，E2E P90 跳变 +15.9%
- **qps-peak-finder**：Phase 1/2/3 全流程
  - Phase 1：peak = 716.9 t/s @ con=120
  - Phase 2：bracket 收敛到 [0.2494 ✅, 0.2529 ❌]，宽 1.4%
  - Phase 3：4 档 × 45min，全部 SLA ✅
  - **ideal_rps = 0.2494 req/s**，与网格搜索偏差 1.8%（交叉验证通过）

### 3. tianji-querysafety-4b-v2-3（天机安全 4B）
- **回放测试**：1422 RPM 峰值，成功率 100%
- **QPS Sweep（4TP）**：低段 4.0~6.59 + 高段 7.5~10.0，合并 34 档
  - 拐点：8.0 → 8.5 req/s，E2E P95 首次超标
  - **SLA 合规最大 QPS = 8.0 req/s（480 RPM）**
- **4TP vs 4DP 对比**：4DP 全 28 档 FAIL（prefill 瓶颈），4TP 有效

### 4. hepan-72b-v1-2（合盘 72B）
- **回放测试**（同事 jyf 执行）：150 RPM 峰值，成功率 99.95%
- **QPS Sweep**：orig 组 + data600 组双路对比
  - SLA 合规最大 QPS = 0.80 req/s（TTFS P90 ≤ 1.6s 基准）

### 5. lingyu-235b-A22b-v9-2（灵宇 235B）
- **QPS Sweep**：1.0~3.0 req/s，21 档（同事 jyf 数据，已迁移分析）
  - 拐点：QPS=2.0 req/s，E2E P90 加速增长
  - 单实例承载 ~120 RPM，业务峰值 800 RPM 需 7 实例

### 6. xinghan-chart-32b-v1-1-agent（Chart 32B Agent）
- **QPS Sweep（8TP + 4TP）**：初轮测至 4.0 req/s（有效余量 15×，拐点未定位）
- **qps-peak-finder**（2026-03-19）：
  - **8TP**：ideal_rps = **7.61 req/s**，TTFS P90 = 1488ms（收敛完成）
  - **4TP**：预计 ideal_rps ≈ 4.2~4.3 req/s（Phase 2 进行中）
  - **Phase 3 网格测试**：8TP 运行中（4 档 × 45min）

---

## 实验状态汇总

| 模型 | 方法 | 状态 |
|------|------|------|
| ziwei-32b | qps-peak-finder Phase 1/2 | 🔄 Phase 2 进行中 |
| guoxue-72b | 网格扫描 + qps-peak-finder | ✅ 全部完成 |
| tianji-4b | QPS Sweep + 回放 | ✅ 全部完成 |
| hepan-72b | 回放 + QPS Sweep | ✅ 全部完成 |
| lingyu-235b | QPS Sweep（含分析） | ✅ 分析完成 |
| chart-32b | qps-peak-finder Phase 1/2/3 | 🔄 Phase 3 运行中 |

The user is asking about what evaluation experiments have been conducted on the machine. Let me summarize the experiments from the project status and progress files.

---
