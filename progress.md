# 📋 项目进度日志 Vol.2（2026-03-23 起）

> **说明**：本文件为 Vol.2，从 2026-03-23 起记录。历史完整记录见：
> - [`progress_archive_vol1.md`](./progress_archive_vol1.md)（截至 2026-03-23，4826 行）

---

## 📌 衔接摘要（截至 2026-03-23）

### 项目背景

对 `xinghan-*` 系列 LLM 模型进行系统性容量评估，覆盖 QPS Peak Finder（三阶段）、回放测试、EVAL_REPORT 生成，并集成在线承载量监控 Dashboard（serve.py + VictoriaMetrics）。

评估流程遵循 `model-evaluation-workflow` Skill（Step 0→7），数据处理使用 `traffic-dataset-prep` Skill，压测使用 `qps-peak-finder` Skill。

---

### 模型评估整体状态（截至 2026-03-23）

| 模型 | QPS 评估 | 回放测试 | EVAL_REPORT | 在线监控 | 状态 |
|------|---------|---------|-------------|---------|------|
| xinghan-hepan-72b-v1-2 | ✅ 完成 | ✅ 完成 | ✅ 完成 | ❌ 未配置 | 🟢 已交付 |
| xinghan-chart-32b-v1-1-agent | ✅ peak-finder | ✅ 99.19% | ✅ 完成 | ❌ 未配置 | 🟢 已交付 |
| tianji-querysafety-4b-v2-3 | ✅（Phase 3 缺 2 档）| ✅ 100% | ⚠️ 待补档 | ✅ 已配置 | 🟡 基本完成 |
| xinghan-ziwei-32b-v1 | ✅ peak-finder | ✅ 历史 | ❌ 未生成 | ✅ v0.4.6 已接入 | 🟡 待 Step 7 |
| xinghan-guoxue-72b-v1-2-reason（8×L20）| ✅ P1~P3 完成 | ⚠️ 待执行 | ❌ 未生成 | ❌ 未配置 | 🟠 进行中 |
| xinghan-guoxue-72b-v1-2-reason（4×H20）| ✅ P1~P3 完成 | ⚠️ 待执行 | ❌ 未生成 | ❌ 未配置 | 🟠 进行中 |
| lingyu-235b-A22b-v9-2 | ✅ 完成 | ❌ 无数据 | ❌ 未生成 | ✅ 已配置 | 🟡 待 Step 7 |

---

### ⚠️ 关键风险提示

| 风险 | 详情 |
|------|------|
| ⚡ **tianji 容量告急** | 8 实例总容量 3840 RPM，7 日峰值 3524 RPM（**91.8%**），需关注扩容 |
| ⚠️ **guoxue L20 容量偏低** | ideal_rps = 0.2114 req/s = 12.7 RPM/实例，业务峰值 256 RPM，需多实例（≥20 实例 8×L20）|
| ⚠️ **guoxue H20 容量较低** | ideal_rps = 0.5878 req/s = 35.3 RPM/实例，256 RPM 峰值需 ≥8 实例 4×H20 |
| ✅ **ziwei 缩容建议就位** | 2 实例 7 日峰值 52 RPM（占 SLA 27%），建议缩至 1 实例节省 8 卡 L20 |

---

### 关键文件路径速查

| 类别 | 路径 |
|------|------|
| 模型结果索引 | `results/models/INDEX.yaml` |
| guoxue L20 Phase 1 checkpoint | `logs/guoxue-v2-eagle3-phase1_20260323_1804/phase1_checkpoint.md` |
| guoxue L20 Phase 2 checkpoint | `logs/guoxue-v2-phase2_20260320_1920/phase2_checkpoint.md`（ideal_rps=0.2114）|
| guoxue L20 Phase 3 结果目录 | `logs/guoxue-v2-phase3_20260322_1754/` |
| guoxue H20 Phase 2 checkpoint | `logs/guoxue-v2-h20-phase2_20260320_2053/`（ideal_rps=0.5878）|
| guoxue H20 Phase 3 结果目录 | `logs/guoxue-v2-h20-phase3_20260322_1754/` |
| guoxue V2 数据集 | `datas/output_guoxue_v2/xinghan-guoxue-72b-v1-2-reason_selected_combined_2days_peak_poisson_256_stitched.csv` |
| Dashboard 服务 | `scripts/serve.py`，PID 4041588，端口 18999，日志 `logs/data-pipeline/serve_18999.log` |

---

### 下次会话优先级

1. **运行 qps-peak-finder-analysis Skill** → 生成 guoxue L20 + H20 各自的 `REPORT.md`
2. **合并 L20 vs H20 结果** → 写入 `model-context.md`，比较两种硬件的容量差异
3. **生成 guoxue EVAL_REPORT.md**（model-eval-report Skill）→ 计算 256 RPM 峰值下的实例数建议
4. **规划 guoxue 回放测试**（可选）→ 确认实际混合部署（4H20+9L20）在 256 RPM 下的表现
5. **ziwei EVAL_REPORT.md**（Step 7）

---

## 以下为 Vol.2 新会话日志（2026-03-23 起）

---

## 🗓️ 2026-03-23 下午场（Agent 调用数据提取交付）

### ✅ 我们实现了哪些功能？

**任务背景**：从 `xinghan-chart-32b-v1-1-agent` 模型的原始下载数据中，提取 Agent 框架调用（`星盘普通` 模型）的原始 JSONL 记录，交付给算法组用于数据输入改造（`prompt2` 字段逻辑转化）。

#### 1. 新增提取脚本 `scripts/data/extract_agent_calls.py`

- 遍历 `xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl`（47,338 行，815MB）
- 过滤条件：`role=a` 中 `extra_data.ai_info.model == "星盘普通"` 或 `bot_id == "agen1754fc4ce3864211b572f4dc54d3"`
- 输出格式：保留完整 JSON Array（3 个 role 全保留），每行一条

#### 2. 生成交付文件

```
datas/xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl
40,315 行 / 716MB
```

- 初次提取得到 41,015 条（含 700 条 `prompt2` 为空的记录）
- 二次过滤：移除 700 条 `prompt2` 为空的记录，最终交付 **40,315 条**

#### 3. 数据质量分析

| 分类 | 数量 | 说明 |
|------|------|------|
| 有效 Agent 调用（有 `prompt2`） | **40,315** | 可用于算法组数据改造 |
| Agent 调用但 `prompt2` 为空 | 700 | 日志写入丢失，已过滤 |
| 异常记录（model/bot_id 均为空） | 307 | 无任何有效字段，已排除 |
| 直接调用（已有 benchmark 数据集） | 6,016 | 非本次任务范围 |

---

### 🐛 我们遇到了哪些问题？

#### 问题 1：提取数量与文档记录不符（41,015 vs 41,320）

- **现象**：脚本首次提取到 41,015 条，文档 `xinghan-chart-32b-v1-1-agent-data-structure.md` 中记录为 41,320 条，差值 305
- **调查**：对全量数据做 `(model, bot_id)` 分布统计，发现 307 条 `model=''、bot_id=None` 的异常记录
- **结论**：异常记录无 `prompt2`、无 `model`、无 `bot_id`，属于日志残缺数据，文档中的估算值包含了这部分，实际有效 Agent 调用为 41,015 条

#### 问题 2：700 条 `prompt2` 为空

- **现象**：41,015 条提取记录中，有 700 条 `prompt2` 字段为空字符串
- **调查**：这 700 条 `model=星盘普通`、`bot_id=agen...` 确认为 Agent 调用，`content` 有正常回复，但 `prompt2` 未写入
- **结论**：线上日志写入偶发丢失（logging bug），Agent 确实执行但参数未持久化，对算法组无利用价值，按用户指示过滤

---

### 🔧 我们是如何解决的？

1. 增量调查：通过全量分布统计锁定异常记录来源，确认提取逻辑正确
2. 二次过滤：用 Python 脚本原地替换，仅保留 `prompt2` 非空记录，最终交付 40,315 条

---


---

## 🗓️ 会话记录 — 2026-03-23（深夜场）：EVAL_REPORT 纠正混合部署 + INDEX.yaml 双配置重构

### 📌 会话目标
1. 修正 EVAL_REPORT.md 中将"当前部署"误写为"仅 6×H20"的问题 → 更新为实际的 6×H20 + 4×L20 混合 10 实例部署
2. 补充 Phase 1 饱和探测摘要与三锚点对照表（EVAL_REPORT 第 4 节扩充）
3. 重构 INDEX.yaml 中 guoxue 条目的极限 QPS 字段：主配置改为 8×L20，H20 以 `_h20` 后缀挂载（方案 A）
4. 更新 xinghan-chart-32b-v1-1-agent 状态 → 重新评估中

---

### ✅ 我们实现了哪些功能？

#### 1. EVAL_REPORT.md 多处混合部署纠正（6 处修改）

用户指出报告多处仍写"6 实例 × 4×H20 临时过渡"，与实际部署（6×H20 + 4×L20）不符。涉及修改：

| 位置 | 改动前 | 改动后 |
|------|--------|--------|
| 摘要表"当前临时方案" | 6×H20（211.8 RPM）| **6×H20 + 4×L20，262.6 RPM，余量 2.6%** |
| §1 部署配置"临时配置" | TP=4（4×H20）| TP=4/8 混合，10 实例 |
| §3 回放压测（残留"测试中"表格）| 4 行旧"🔄 测试中"表格 | **删除**（已有完成结果） |
| §5 流量说明注脚 | "6×H20 过渡，17% 容量缺口" | "混合部署 262.6 RPM，余量仅 2.6%" |
| §6 当前方案表格 | 单列 H20 表（211.8 RPM，17% 缺口）| **三列对比表**（H20 部分 / L20 部分 / 合计） |
| §6 运维建议第 5 条 | "回放测试结果出来后…" | "回放测试已完成（99.89%），持续监控峰值" |

#### 2. EVAL_REPORT.md §4 扩充：三锚点对照 + Phase 1 饱和探测摘要

新增两个小节，补充之前缺失的极限 QPS 内容（model-evaluation-workflow Skill Step 6 要求）：

**新增 §4.2 三锚点对照**：
| 操作点 | 8×L20 | 4×H20 |
|--------|-------|-------|
| 极限 RPS（Phase 2 首档，饱和区）| 0.2498 req/s（15.0 RPM）| 0.7348 req/s（44.1 RPM）|
| 理想 RPS（SLA 合规上限）| 0.2114 req/s | 0.5878 req/s |
| 服务端承载并发（Little's Law）| 32 | 46 |

**新增 §4.4 Phase 1 饱和探测摘要**：L20（con20/30/40）和 H20（con60/120）各档吞吐变化，含 max_rps_estimate 估算说明。原 §4.2/4.3 顺移为 §4.3/4.5。

#### 3. INDEX.yaml guoxue 条目双配置重构（方案 A：主从后缀）

参考 `xinghan-chart-32b-v1-1-agent` 使用 `_4tp` 后缀的惯例，以 `_h20` 后缀区分两套配置：

- **主配置（无后缀）= 8×L20**：`saturation_rps` 从 0.7348（H20）改为 **0.2498（L20）**，相关并发/吞吐/延迟全套更新
- **新增 `_h20` 后缀字段**：`sla_max_qps_rps_h20=0.5878`、`saturation_rps_h20=0.7348` 等全套 H20 极限数据
- **新增效率对比**：`h20_vs_l20_qps_ratio: 2.78`、`h20_vs_l20_per_card_ratio: 5.56`
- `current_interim` → `current_mixed`，更新描述为"6×H20 + 4×L20，共 10 实例，262.6 RPM（余量 2.6%）"
- `recommendation` 更新为反映混合部署现状和 L20 长期目标

#### 4. INDEX.yaml chart-32b 状态更新

用户告知 V1 评估结果与线上监控 double check 后发现数据存疑：

| 字段 | 改动前 | 改动后 |
|------|--------|--------|
| `eval_status` | `completed` | `re_evaluating` |
| `eval_completed_date` | `"2026-03-20"` | `null` |
| 新增 `reeval_reason` | — | V1 数据与线上监控对比发现偏差 |
| 新增 `reeval_status` | — | 2026-03-23 已对接算法，预计 2026-03-25 开始构建新数据集 |
| `recommendation` | ✅ 可上线 | ⚠️ 结论挂起，V2 重测进行中 |

---

### 🐛 我们遇到了哪些问题？

#### 问题 1：StrReplace 工具多次对含全角字符的行匹配失败
- **现象**：`EVAL_REPORT.md` 中含「×」「（）」等全角字符的表格行无法精确匹配，报 "not found" 错误
- **解决**：改用 Python 脚本（`open/replace/write`）绕过工具限制，精确替换成功

#### 问题 2：INDEX.yaml 原 saturation_rps 为 H20 数据（主配置标注却是 L20）
- **现象**：用户在 Dashboard 看到极限 QPS 为 0.7348（H20），但主配置标注为 8×L20，存在矛盾
- **解决**：经 brainstorming 讨论三个方案，用户选方案 A（主从后缀），将 L20 数据作为主配置，H20 以 `_h20` 后缀补充

---

### 🔧 我们是如何解决的？

1. StrReplace 失败 → Python `content.replace()` 直接字符串替换，通过逐行打印 `repr()` 确认精确内容
2. 混合部署纠正 → 逐一列举 6 处问题位置，Python 脚本一次性批量完成修正
3. INDEX.yaml 双配置 → brainstorming Skill 提出 3 方案（主从后缀 / 嵌套块 / 注释保留），用户选 A，Python 脚本精确整块替换

---

## 🗓️ 会话记录 — 2026-03-23（晚场）：guoxue 资产清理 + 生产锚点补测

### 📌 会话目标
1. 对 xinghan-guoxue-72b-v1-2-reason 的历史资产（V1 兜底数据实验）进行归档清理
2. 基于 V2 真实数据重写 EVAL_REPORT.md，修正业务峰值口径（43→256 RPM）
3. 更正部署方案叙述（L20 为长期目标，H20 为临时过渡）
4. 修复 Phase 3 "生产 RPM 锚点" 标注错误（0.05 → 实测 0.195 req/s），补跑 L20 实测档

---

### ✅ 我们实现了哪些功能？

#### 1. V1 旧实验目录归档（物理移动）

将以下 4 个使用兜底数据的实验目录移入 `results/archive/guoxue-v1-deprecated/`：
- `guoxue_partial_20260317/`
- `guoxue_qps_sweep_20260317/`（V1 ideal=0.245 req/s，SLA E2E≤150s，业务峰值口径仅 43 RPM）
- `guoxue_qps_peak_finder_20260318/`（V1 ideal=0.2494 req/s）
- `xinghan-guoxue-72b-v1-2-reason_qps_sweep_20260316/`（V1 早期分段）

创建 `results/archive/guoxue-v1-deprecated/ARCHIVED.md` 说明废弃原因。

#### 2. 全量文档更新（5 个文件）

| 文件 | 主要变更 |
|------|---------|
| `results/README.md` | 旧 guoxue 条目标注"已归档"，新增 V2 三个实验详细说明节 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | dataset_path 切换 V2，business_peak_rpm 修正，回放状态更新 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md` | **完全重写**，V2 数据，L20 为主方案，H20 为临时，新增 L20 流量说明节 |
| `results/models/INDEX.yaml` | deployment 改回 L20，sla_max_qps_rps 从 0.5878 修正为 0.2114，recommendation 按用户要求重写 |
| `results/guoxue-v2-8tp-peak-finder-20260323/REPORT.md` | Phase 3 表格新增 0.1950 req/s 生产锚点实测行 |

#### 3. EVAL_REPORT.md 关键结论变更

| 项目 | 旧（V1 错误）| 新（V2 正确）|
|------|------------|------------|
| 业务峰值 | 43 RPM（stream only）| **256 RPM**（stream 43 + MCP 八字深度 213）|
| 推荐方案 | 4 实例 × 8L20 = 32 卡 | **≥20 实例 × 8L20（推荐20实例=160卡）** |
| 主配置 | L20（混淆为 H20 推荐）| **L20（长期目标）；H20 6实例为临时过渡** |
| 单实例上限 | 14.96 RPM（V1 SLA E2E≤150s）| **12.7 RPM**（V2 SLA E2E≤180s）|

#### 4. Phase 3 生产锚点补测（L20 @ 0.195 req/s）

- 识别问题：Phase 3 最低档 0.05 req/s 与 Grafana 实测生产 RPS 0.195 req/s 差 4 倍，"生产 RPM 锚点"标签名不副实
- 解决方案：补跑单档 1 小时测试（0.195 req/s，843 请求，1.2× buffer）
- **测试结果**：✅ SLA 全部通过
  - 实际发送：703 条，成功率：100.0%（140 条为 buffer 超时未发，status=-5）
  - TTFS P90：730 ms（< 1500ms ✅）
  - E2E  P90：152.2 s（< 180s ✅，裕量 15.4%）
- 日志目录：`logs/guoxue-v2-8tp-prod-anchor_20260323_155707/`
- 新增脚本：`scripts/benchmark/run_prod_anchor_guoxue8tp.sh`

#### 5. Dashboard（serve.py）自动更新

`serve.py` 读取 INDEX.yaml 响应每次请求，无需重启，所有 INDEX.yaml 变更立即生效。

---

### 🐛 我们遇到了哪些问题？

#### 问题 1：StrReplace 工具对含全角标点的中文行匹配失败
- **现象**：多次尝试替换含「（）」等全角字符的中文行失败
- **解决**：改用 Python 脚本 `content.replace(old, new)` 直接字符串替换

#### 问题 2：EVAL_REPORT.md 最初将 H20 错写为"推荐方案"
- **现象**：用户指出 H20 只是因 L20 资源不足的临时部署（6实例 × 4H20），长期方案是 L20
- **解决**：重新梳理叙述逻辑——L20 为主，H20 为过渡；新增 §5「L20 在线流量说明」，明确各场景所需实例数

#### 问题 3：INDEX.yaml 显示拐点 0.5878（H20 值）而非 L20 值
- **现象**：用户在 Dashboard 看到拐点显示为 0.5878（H20 的 ideal_rps），但部署标注为 8×L20
- **解决**：将 `sla_max_qps_rps` 从 0.5878 修正为 0.2114，`sla_max_qps_rpm` 从 35.3 修正为 12.7

#### 问题 4：生产锚点补测成功率显示 83.4%
- **现象**：初始统计成功率 83.4%（703/843）
- **解决**：分析 status 分布，确认 140 条 status=-5 为 TIMELIMIT buffer 未发送请求，实际发出 703 条全部成功 → 真实成功率 **100%**

---

### 🔧 我们是如何解决这些问题的？

1. 文本替换失败 → 改用 Python `open/replace/write` 绕过 StrReplace 的全角字符限制
2. 叙述方向错误 → 用户纠正后，重写 EVAL_REPORT §1 摘要、§5 L20 流量说明、§6 部署建议三节
3. INDEX.yaml 数值错误 → Python 脚本精确替换两处字段
4. 成功率虚低 → status 分布分析确认 -5 = buffer 未发送，重新以实发数为分母计算

---

### ⚠️ 未完成事项

1. **回放测试（guoxue H20）结果待补充**：测试于 2026-03-23 14:56 启动，已完成（2319 行日志），但未读取结果写入 EVAL_REPORT.md §3 和 INDEX.yaml
2. **H20 生产锚点补测**：0.195 req/s 单档，用户需先调整 endpoint URL，待用户操作后再跑
3. **H20 REPORT.md Phase 3 更新**：待 H20 生产锚点跑完后，同样为 `guoxue-v2-h20-peak-finder-20260323/REPORT.md` 增加 0.195 行并重标 0.05 档

---

## 🗓️ 会话记录 — 2026-03-23（夜场）：guoxue 4H20+9L20 回放分析 & EVAL_REPORT 更新

### 📌 会话目标

1. 确认 4×4H20 + 9×8L20 新部署方案回放测试已完成
2. 离线分析回放结果，撰写 REPORT.md（含与基线方案横向对比）
3. 更新 EVAL_REPORT.md，反映新方案指标及当前部署状态

---

### ✅ 我们实现了哪些功能？

#### 1. 确认回放测试完成

通过 `ps -ef | grep replay` 确认 PID 168511 进程已结束。日志末行：

```
总样本数: 6358 / 成功: 6358 / 成功率: 100.00%
```

测试时长：17:26 → 18:20（约 54 分钟），CSV 产出：6.3 GB。

#### 2. 离线统计分析（offline_analysis.py）

启动 PID 214183，处理 6.3GB CSV，内存峰值约 28GB，运行约 5 分钟完成。

| 关键指标 | 值 |
|---------|-----|
| 成功率 | **99.89%**（6351/6358）|
| TTFT P90 | **1.029 s**（SLA ≤1.5s，余量 31%）|
| TTFS P90 | **1.182 s**（SLA ≤1.5s，余量 21%）|
| E2E P90 | **115.468 s**（SLA ≤180s，余量 36%）|
| E2E P99 | **148.774 s** |
| Decode 吞吐 | **5,610 tokens/s** |

产出：`results/guoxue-v2-4h20-9l20-replay-20260323/`（HTML + 7 张 PNG）

#### 3. 撰写 REPORT.md（含双方案横向对比）

新建 `results/guoxue-v2-4h20-9l20-replay-20260323/REPORT.md`，包含：
- 部署背景（1H20≈5L20 换算动机）
- 完整延迟指标（TTFT/TTFS/E2E 各分位数）
- **与基线方案（6H20+4L20）横向对比表**
- 容量分析（对三月峰值 195 RPM 余量 +31%）
- 风险提示（E2E P99=148.8s 达 SLA 的 83%）

两方案对比汇总：

| 指标 | 6H20+4L20（基线）| 4H20+9L20（当前）| 变化 |
|------|:--------------:|:------------------:|:----:|
| 成功率 | 99.89% | 99.89% | = |
| TTFT P90 | 0.989s | 1.029s | +4.0% |
| TTFS P90 | 1.139s | 1.182s | +3.8% |
| E2E P90 | 100.7s | 115.5s | +14.7% |
| E2E P99 | 121.2s | 148.8s | +22.8% |

#### 4. 归档文档更新（4 个文件）

| 文件 | 操作 |
|------|------|
| `results/README.md` | 目录表 + 详细节各新增 4H20+9L20 回放条目 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | 追加 `replay2_*` 字段（6 个） |
| `results/models/INDEX.yaml` | 追加 `replay2_*` 字段 + linked_experiments 新增条目 |
| `progress.md` | 本条记录 |

#### 5. EVAL_REPORT.md 增量更新

使用 `model-eval-report` Skill 增量修改模式，针对 5 处进行更新：

| 位置 | 修改内容 |
|------|---------|
| 摘要表（L17-21）| 上线建议改为两轮通过；当前部署更新为 4H20+9L20；风险提示改为 E2E P99 近 SLA |
| 摘要备注（L24）| 从"余量仅 2.6%"改为新方案"三月峰值余量 +31%" |
| 第 3 节回放结论 | 改为方案一/方案二双表格，各含完整 SLA 指标 + 报告链接 |
| 第 6 节部署配置 | 实例数 6+4→4+9，GPU 总数 56→88，总承载 262.6→255.5 RPM，运维建议同步 |
| 实验索引 + 脚注 | 新增两行回放实验条目，脚注更新为双回放汇总 |

---

### 🐛 我们遇到了哪些问题？

#### 问题 1：offline_analysis.py 用 `usecols` 读 CSV 失败

- **现象**：指定 `usecols=['status', 'ttft_s', 'e2e_s']` 时报 `ValueError: Usecols do not match columns`
- **根因**：回放 CSV 的列名是原始格式（`token_list` 等），ttft_s/e2e_s 是分析脚本内部计算列，不存在于原始 CSV
- **解决**：让 `offline_analysis.py` 完整运行，从日志输出中提取各分位数指标

#### 问题 2：EVAL_REPORT.md 含全角字符，StrReplace 无法匹配

- **现象**：StrReplace 对含「⚠️」「×」等字符的行匹配失败（与之前同类问题一致）
- **解决**：使用 Python `open + f.readlines() + 按行号定位` 精确替换；部分大块替换用 `content.replace()` + 逐行 `repr()` 调试

---

### 🔧 我们是如何解决这些问题的？

1. CSV 列名问题 → 改为完整运行分析脚本，从 log 输出提取结构化指标行
2. StrReplace 全角字符问题 → Python 脚本组合策略：
   - 行号精确定位（`f.readlines()[lineno-1]` 替换）
   - 大块替换用 `content.replace(old, new)` + assert 校验存在性
   - 调试时 `repr(content[idx:idx+200])` 确认确切字符

---

### ⚠️ 未完成事项

1. **H20 回放测试（6H20+4L20，14:56 启动）**：结果已分析归档（另见基线 REPORT.md），但 EVAL_REPORT.md §3 基线表中 TTFS P90 字段来源已确认（1.139s）✅
2. **H20 生产锚点补测**（原遗留）：用户需调整 endpoint URL → 执行 `run_prod_anchor_guoxue4h20.sh`
3. **H20 REPORT.md Phase 3 更新**：待生产锚点跑完后补充 0.195 req/s 行

---

## 2026-03-24 Session — Eagle3 8×L20 QPS Peak Finder 分析归档

### ✅ 我们实现了哪些功能？

#### Step 6 — qps-peak-finder-analysis（REPORT.md 生成）

对昨日执行的 guoxue-72b Eagle3 8×L20 三阶段压测（Phase 1 + Phase 2 + Phase 3）完成结果分析：

| 步骤 | 产物 |
|------|------|
| Little's Law 计算（Phase 1 峰值档 con=50）| server_concurrency ≈ 37（0.2641 × 142.9s）|
| Phase 2 + Phase 3 合并目录 | `logs/guoxue-v2-eagle3-phase23_merged_20260323/`（8档）|
| 容量曲线图表生成 | `results/guoxue-v2-eagle3-8l20-peak-finder-20260323/*.html` |
| REPORT.md 生成 | `results/guoxue-v2-eagle3-8l20-peak-finder-20260323/REPORT.md` |

**三锚点摘要**：

| 操作点 | RPS | TTFS P90 | E2E P90 | 成功率 |
|--------|-----|---------|---------|--------|
| 极限 RPS（Phase 2 首档 FAIL）| 0.3486 req/s | 1.416s | 289.4s | 100% |
| 理想 RPS（Phase 2 收敛）| **0.3169 req/s（19.0 RPM）** | 0.769s ✅ | 172.1s ✅ | 99.9% ✅ |
| 生产 RPM 锚点（Phase 3 最低档）| 0.1950 req/s（11.7 RPM）| 0.754s ✅ | 96.2s ✅ | 99.9% ✅ |

**Eagle3 vs vanilla 8×L20**：ideal_rps 从 0.2114 提升至 0.3169，提升 **+50%（1.50×）**

#### Step 6.5 — 实验目录归档

| 文件 | 操作 |
|------|------|
| `logs/guoxue-v2-eagle3-phase1_20260323_1804/README.md` | ✅ 新建 |
| `logs/guoxue-v2-eagle3-phase2_20260323_1923/README.md` | ✅ 新建（标注数据无效，污染原因） |
| `logs/guoxue-v2-eagle3-phase2_20260323_2054/README.md` | ✅ 新建（有效运行） |
| `logs/guoxue-v2-eagle3-phase3_20260324_0153/README.md` | ✅ 新建 |
| `results/README.md` | ✅ 新增 eagle3 条目（目录总览 + 详细说明）|
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | ✅ 追加 `eagle3_8l20_*` 字段段落 |
| `results/models/INDEX.yaml` | ✅ linked_experiments 追加 eagle3 实验路径 |

---

### 🐛 我们遇到了哪些问题？

#### 问题 1：Phase 2 第一次运行数据污染

- **现象**：Phase 2 首档（rps=0.3169）TTFS P90=124.7s（正常 <1.5s），所有档位 FAIL，触发 PRODUCTION_FLOOR 托底
- **根因**：Phase 1 con=80 刚结束，服务器大量在途请求未排空，Phase 2 立即启动被污染
- **解决**：等服务完全冷却后重新执行 Phase 2，第二次（2054）结果正常

#### 问题 2：token_list decode_throughput 与 metrics_cache 数值不一致

- **现象**：手动用 token_list 时间戳计算得 220.8 t/s，而 metrics_cache.json 记录 573.5 t/s
- **根因**：脚本实际使用 `old_response_len`（参考响应 token 数 ~2172）计算吞吐，非实际生成 token 数（token_list 长度 ~836）；两种方法 max_rps_estimate 结果一致（0.2641）因为比值相同
- **解决**：理解差异后统一使用 checkpoint 记录值（573.5 t/s，avg_out=2172）确保与脚本结论对齐

---

### 🔧 我们是如何解决这些问题的？

1. 测试污染识别 → 通过对比第一次（1923）和第二次（2054）同档位结果，确认 TTFS P90 从 124.7s→0.746s 完全是污染所致，作废第一次数据
2. 指标计算差异 → 检查 metrics_cache.json 发现数值与 checkpoint 吻合（573.5 t/s），手动计算 max_rps 结果 0.2641 与两者一致，确认 checkpoint 正确

---

### ⚠️ 未完成事项

1. Eagle3 vs vanilla 8×L20 详细对比（EVAL_REPORT.md 未更新 Eagle3 章节）
2. 4×H20 + Eagle3 部署组合评估（如需进一步比较）

---

---

## 🗓️ 2026-03-24 下午场会话

### ✅ 实现的功能

#### Step A — guoxue 4×H20 Phase 3 数据有效性核查

**背景问题：** 发现 `logs/` 中同时存在三个 guoxue-v2-h20-phase3 目录，需要判断哪个有效。

**分析过程：**

1. **识别并发污染**：确认 `guoxue-v2-h20-phase3_20260322_1754` 和 `guoxue-v2-h20-phase3_20260322_1759` 在 3月22日 17:54 和 17:59 几乎同时启动，使用**完全相同**的 endpoint / dataset / QPS 档位，属于并发双路压测，严重抢占服务资源。

2. **统计指标对比验证**（通过解析 token_list 计算 TTFS / E2E）：

| 指标 | 1754/1759（3/22并发） | 1024（3/23独立） |
|---|---|---|
| qps_0.4085 成功率 | 44~45% | **83.3%** |
| qps_0.4085 timeout(-3) | **677~690 个** | **0 个** |
| qps_0.4085 TTFS P90 | **194~195s** | **0.52s** |
| qps_0.5878 成功率 | **11.6~11.7%** | **83.3%** |
| qps_0.5878 timeout(-3) | **1819~1822 个** | **0 个** |
| qps_0.5878 TTFS P90 | **273~274s** | **0.52s** |

3. **确认有效版本**：`guoxue-v2-h20-phase3_20260323_1024` 是 3月23日独立重测，数据完全干净：
   - 全部 4 档 **timeout = 0**
   - cancel 率精确等于 **16.7%**（=1 - 1/1.2，符合 num_requests 超发设计）
   - E2E P90 严格单调递增：81.7s → 85.9s → 97.8s → 114.9s ✅
   - `qps_0.0500` 档位从 3/22 run 硬链接复用，低负载下三次运行指标完全一致，可信
   - `logs/guoxue-v2-h20-phase23_merged_20260323/` 的 argv 确认指向 1024 版本

4. **1754/1759 目录已被删除**，仅 1024 保留。

---

#### Step B — logs 日志归档清理

**背景：** `logs/data-pipeline/` 下堆积了 58 个 `.log` 文件，其中大量对应目录已删除或已入 archive。

**执行过程：**
1. 列出所有活跃子目录（40 个），建立匹配规则
2. 对 58 个 data-pipeline log 逐一人工精确核定（自动匹配有误判，手动修正了时间戳不精确匹配的假阳性）
3. 创建 `logs/archive/data-pipeline/` 目录
4. 移动 **37 个**孤立/过期 log 到归档，保留 **21 个**活跃 log

**归档分类：**

| 类型 | 文件数 | 说明 |
|---|---|---|
| chart 全系列（旧 QPS sweep + xinghan-chart-*） | 23 个 | archive/chart-32b-* 已有数据目录 |
| tianji 旧 QPS sweep | 4 个 | archive/tianji_* 已有数据目录 |
| ziwei 旧 QPS sweep | 3 个 | archive/ziwei_* 已有数据目录 |
| 旧 guoxue（2016-03） | 5 个 | archive/guoxue_* 已有数据目录 |
| h20 phase3 1759（已删目录） | 1 个 | `guoxue-v2-h20-phase3_20260322_1759` 已删 |
| 杂项（serve_18999 等） | 1 个 | 无对应活跃目录 |

**`logs/*.log` 无需归档**（7 个全部对应现有活跃目录）：
- `relay_eagle3_l20_*.log` → `guoxue-v2-eagle3-phase2_20260323_2054` 活跃
- `phase3_grid_guoxue8tp_v2_20260322_1754.log` → `guoxue-v2-phase3_20260322_1754` 活跃

---

### 🐛 遇到的问题

#### 问题 1：自动模糊匹配误判多

- **现象**：Python 脚本基于关键词自动匹配日志与目录，产生多个假阳性（如 `chart-32b-8tp_replay_20260320_142856.log` 被匹配到 `145239` 目录，时间戳不同）
- **根因**：日志命名与目录命名不严格对应（不同时间戳、旧命名惯例）
- **解决**：人工逐一核定，对关键文件（如 `guoxue_v2_h20_phase3_20260322_175900.log`）确认对应目录已删除，最终精确 37/21 分组，全覆盖无遗漏

---

### ⚠️ 未完成事项

- Eagle3 4×H20 Phase 2 进行中（`guoxue-v2-eagle3-4h20-phase2_20260324_1236/` 等），待完成后继续 Phase 3
- EVAL_REPORT.md 中 Eagle3 章节仍未追加

---

#### Step 6 补充 — 三阶段决策逻辑说明

对用户的提问「Phase 1→Phase 2→Phase 3 每个阶段如何决策」进行了完整说明：

| 阶段 | 决策机制 | 本次实例 |
|------|---------|---------|
| Phase 1 | 两段式步进：增幅>10% 翻倍；1~10% 线性+10；<1% 停止 | con40→50(+4.8%,+10步进)→60(-13.2%,饱和确认) |
| Phase 2 | 比例快速逼近（无bracket）+ 几何中点精查（有bracket）| 0.3169 PASS→0.3486 FAIL建立bracket→0.3324→0.3246收敛(2.43%<3%) |
| Phase 3 | linspace(prod_rps, ideal_rps, 4) 均匀验证网格 | 4档全PASS，容量曲线单调正常 |

---

#### Step 清理 — 无效日志目录删除

**识别并清理测试污染数据：**

| 清理对象 | 类型 | 大小 | 原因 |
|---------|------|------|------|
| `logs/guoxue-v2-eagle3-phase2_20260323_1923/` | 目录 | 485 MB | Phase 2 首次运行测试污染（TTFS P90=124.7s，正常<1.5s）|
| `logs/data-pipeline/guoxue_eagle3_phase2_20260323_192312.log` | 日志 | 63 KB | 对应上述污染运行的 log |
| `logs/data-pipeline/guoxue_eagle3_phase2_20260323_184311.log` | 日志 | 8.4 KB | 18:43 的早期 abort 尝试，无对应数据目录 |

**保留确认（有效数据）：**
- `guoxue_eagle3_phase1_supp_20260323_184921.log`：Phase 1 补充测试（con=50/60/70），有效
- `eagle3_l20_phase2_20260323_2054.log` / `eagle3_l20_phase3_20260323_2056.log`：有效运行 log
- `phase23_merged`：硬链接目录，`du` 显示 3.6G 但实际不额外占磁盘

---

#### Step 6 补充 — REPORT.md 完善（对照 vanilla REPORT 格式）

参考 `results/guoxue-v2-8tp-peak-finder-20260323/REPORT.md` 补全 Eagle3 报告缺失内容：

| 补充项 | 内容 |
|--------|------|
| §0 RPM 列 | 新增 RPM 换算列（19.0 RPM / 20.9 RPM 等） |
| §1 峰值档独立指标表 | 新增 7 行指标表（对齐 vanilla 格式） |
| §2 "Round N" 格式 | 从"序"改为"Round N"，补齐列标题 |
| §3 P50 / P99 数据 | 实测提取（Python 解析 token_list）并填入完整表格 |
| §3 长尾提示 | P99=207.7s 超 SLA，提示建议保守上限 0.2763 req/s |
| Eagle3 vs Vanilla 对比表 | ideal_rps 1.50×、极限 RPS +40%、吞吐 +59%、E2E P90 +12% |
| 拐点分析 | 补充完整文字分析（prefill 无瓶颈 / decode queue 积压信号）|
| 上线建议 保守/激进区分 | 保守：0.28 req/s（P99友好）/ 激进：0.317 req/s + 告警阈值 0.325 req/s |

---

### 🐛 本段新增问题

#### 问题 3：phase23_merged du 显示 3.6G 令人困惑

- **现象**：`du -sh` 显示合并目录 3.6G，而 phase2+phase3 实际才合计 3.6G，看起来像是翻倍了
- **根因**：`cp -rl`（硬链接）创建，`du` 对硬链接文件重复计数，实际磁盘占用未增加
- **确认方式**：`ls -li` 对比 inode 号，merged 目录与原目录文件 inode 完全一致
- **解决**：理解硬链接特性，保留 merged 目录，不做误删

---

---

## 📅 2026-03-24 晚场 — chart-32b Agent 数据 prompt2 转换

### ✨ 我们实现了哪些功能？

#### 1. 分析 Agent 框架调用记录的数据结构

- 数据文件：`datas/xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl`（40,315 条）
- 每条记录是 3-item JSON 数组（role=b/ib/a）
- `role=a`（index 2）的 `prompt2` 字段含结构化参数，`prompt` 字段为空 `[]`
- 转换接口：`POST http://172.21.8.42:1324/v1/chat/completions/messages`
  - 输入：`prompt2` JSON（含 `profile_info_list`、`chart_ext_param`、`query` 等）
  - 输出：`{"messages": [system_msg, user_msg]}`
  - system message：完整星盘专家 system prompt（约 1100~3400 字符，含角色、策略、规则及本次查询提取的星盘相位数据）
  - user message：原始 query 包装为模板格式（含出生日期、性别、年龄、提问时间）

#### 2. 单条数据验证（Demo）

- 取第 1 条记录，提取 `prompt2`，调用接口
- 验证结果：返回 2 条 messages，system 长度 2619 字符，user 长度 98 字符 ✅
- 确认 user message 也经过了模板化转换（不只是 system 被动态生成）

#### 3. 编写批量转换脚本

**脚本路径**：`scripts/data/convert_chart_agent_prompt2.py`

**核心设计**：
- 并发：`ThreadPoolExecutor(max_workers=5)`（服务端限制 5 并发）
- 重试：每条最多 3 次，指数退避（2s、4s）
- 有序写出：`buffer` + `write_ptr` 保证输出顺序与输入一致
- 续传：`count_lines(OUTPUT) + count_lines(ERROR)` 计算已处理条数，重启自动跳过
- 输出：`role=a.prompt` 由 `[]` 填充为 `[system_msg, user_msg]`
- 错误日志：`{line_no, error}` 写入独立 error JSONL

**输出文件**：
| 文件 | 说明 |
|------|------|
| `datas/output_chart/xinghan-chart-32b-v1-1-agent_calls_converted.jsonl` | 转换后主输出 |
| `datas/output_chart/xinghan-chart-32b-v1-1-agent_calls_errors.jsonl` | 失败记录日志 |

#### 4. 脚本验证与后台启动

- 用 20 条数据冒烟测试：20/20 成功，输出结构正确 ✅
- 后台启动：`nohup python3 scripts/data/convert_chart_agent_prompt2.py > logs/convert_chart_agent_prompt2.log 2>&1 &`
- **PID**：1200975
- 当前进度（约 19:46）：已处理 **5,956 条**（14.6%），速率 ~0.75 条/s，错误 1 条

---

### 🐛 我们遇到了哪些错误？

#### 问题 1：冒烟测试时 `__file__` 未定义

- **现象**：用 `exec(code)` 动态执行脚本时，`Path(__file__)` 报 `NameError: __file__`
- **根因**：`exec()` 上下文中无 `__file__` 变量
- **解决**：改用直接内联逻辑的独立 Python 片段做 20 条验证，不再 exec 脚本文件

#### 问题 2：日志文件起初为空

- **现象**：进程启动后 60 秒内 `convert_chart_agent_prompt2.log` 无内容
- **根因**：Python 重定向到文件时默认缓冲；且 `REPORT_EVERY=200`，第一次打印需等 200 条完成
- **解决**：已在 `print(..., flush=True)` 确保输出及时；第 200 条后日志正常输出

---

### ✅ 本段无遗留问题，任务正在后台持续执行

---

## 🗓️ 2026-03-24 下午场（17:00~19:00）— EAGLE3 4×H20 Phase 2 分析 + 单点探测启动

### ✨ 我们实现了哪些功能？

#### 1. 修正 EVAL_REPORT.md 中 H20 数据三处错误

文件：`results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md`

| # | 位置 | 修正前 | 修正后 | 原因 |
|---|------|--------|--------|------|
| 1 | §4.2 服务端承载并发 | `70（L=λW, Phase 1 con70）` | `57（L=λW，Phase 3 ideal档 E2E P50=96.2s）` | Phase 1 根本无 con=70 测试；原值是错误混用 EAGLE3 E2E(143s) 反算的 |
| 2 | §4.2 peak decode 吞吐 | `1260.3 tok/s（Phase 1）` 单行 | 拆为两行：Phase 1 con60=1056.7；Phase 3 ideal档=**1260.3 tok/s** | Phase 1 实测是 1056.7，1260.3 是 Phase 3 的数字，两者含义不同 |
| 3 | §4.4 Phase 1 注释 | "两者相近，说明 Phase 1 估算准确" | L20 差 4% ✓；H20 差 **50% ✗**，原因：只测 con=60/120 两档，加 ⚠️ 说明 | H20 的 Phase 1 max_rps(0.490) 与 Phase 2 极限 RPS(0.7348) 差 50%，不是"相近" |

#### 2. 分析 EAGLE3 4×H20 Phase 2 进展（rps0.3415 & rps0.4519）

**Phase 2 二分搜索路径**（起点：LO=0.195, HI=0.5981）：

| 轮次 | RPS | E2E P90 | TTFT P90 | 成功率 | SLA | 承载并发(L=λW) |
|------|-----|---------|----------|--------|-----|--------------|
| Round 1 | 0.3415 | **44.8s** | 0.489s | 90.88%（137 末尾截断） | ✅ | 12.4 |
| Round 2 | 0.4519 | ~320s（推算） | — | 未完成 | ❌ 严重过载 | **144**（异常） |

- `rps0.3415` 通过 SLA（E2E/TTFT 优秀），137 次 status=-5 是测试窗口末尾 in-flight 截断，非服务问题
- `rps0.4519` 服务端 #running-req=144，L=λW 反推 E2E≈320s，是 **EAGLE3 陡崖型拐点**的体现
- EAGLE3 特征：con=60 E2E P90=173s（恰在 SLA 边界），con=120 直接崩溃；真实 ideal_rps 预计在 **0.38~0.42 req/s** 附近

#### 3. Kill Phase 2 + 服务重启 + 单点探测启动

- Kill PID 1111021（bash脚本）+ 1166703（python subprocess），用户更新服务参数
- 服务重启后确认：`/health` 返回 200，推理端点冒烟测试 ✅
- 启动单点探测：RPS=0.5878（vanilla H20 ideal_rps），num_requests=2117，时长约 1h
  - PID：`1218813`
  - 日志：`logs/eagle3-4h20-probe-rps0.5878_20260324_1758/probe.log`
  - 状态：正在进行中（17:58 启动，预计 ~19:00 完成）

---

### 🐛 我们遇到了哪些错误？

#### 问题 1：单点探测第一次失败（404 Not Found）

- **现象**：`probe.log` 第 94 行 `Exception: 探路请求失败: Not Found`
- **根因**：用户更新服务时尚未完成上线，端点路由不存在
- **解决**：先用 `curl /health` + 冒烟请求确认服务在线后，再重新启动探测

#### 问题 2：进程 kill 后 shell 出现 120s 延迟退出

- **现象**：`kill 1166703 1111021` 命令等待了约 2 分钟才返回
- **根因**：kill 信号发送后 shell 等待子进程完全退出；Python benchmark 有 graceful shutdown 逻辑
- **解决**：属正常现象，进程已全部终止

---

### ✅ 本段已完成内容

1. EVAL_REPORT.md H20 三处数据修正 ✅
2. Phase 2 rps0.3415 结果解析（E2E P90=44.8s, avg_output_len=2221） ✅
3. Phase 2 rps0.4519 异常诊断（144并发=陡崖过载） ✅
4. 单点探测 rps0.5878 重新启动 ✅（进行中）

---

## 2026-03-25：guoxue-v2-h20 qps_0.5878 单点深度分析

### 📌 任务目标

对 `logs/guoxue-v2-h20-phase23_merged_20260323/qps_0.5878` 进行 benchmark-result-analysis，整合离线 CDF 分析与 Grafana 实时监控。

### ✅ 实现功能

#### 1. 离线 CDF 分析（`offline_analysis.py`）
- 分析 `guoxue_v2_h20_phase3_qps0.5878.csv`（Phase 3，2026-03-23，2117条请求）
- 生成 HTML 报告：`results/guoxue-v2-h20-peak-finder-20260323/qps0.5878_analysis.html`（1295KB）
- 导出 7 张 PNG：ttft_cdf / ttfs_cdf / user_tpot_cdf / itl_cdf / e2e_cdf / concurrency_timeline / success_rate_timeline
- 核心指标：成功率 99.91%，TTFT P90=0.522s，E2E P90=114.9s，Decode=1260.4 tok/s

#### 2. Grafana 实时监控查询
- 通过 VictoriaMetrics PromQL API 查询部署 `xinghan-guoxue-p72b-v12-reason-h20-tp4`
- 时间段：2026-03-20 20:53–21:53（Phase 2 执行窗口）
- 发现正确指标格式为 `sglang:*`（旧版 recording rule，带冒号）
- 获取 QPM：峰值 41 RPM，均值 34.2 RPM
- 获取 Concurrency：max=62，mean=56.6（与 Little's Law 估算 55.2 误差 2.5%）
- 获取 TTFT P90：均值 0.587s，峰值 0.723s
- 获取 ITL P90：均值 39.3ms
- 获取 E2E P90：均值 170.7s，峰值 182.6s（见差异说明）

#### 3. 综合报告撰写
- 新建 `results/guoxue-v2-h20-peak-finder-20260323/qps0.5878_analysis_REPORT.md`
- 包含：SLA 判定表、CDF 分位数详表、Grafana 监控数据、E2E 差异机理说明、有效性论证
- Grafana E2E P90（170.7s）与离线 P90（114.9s）差异原因：Phase 2 vs Phase 3 测试条件差异 + histogram_quantile 插值精度

#### 4. 归档操作
- 新建 `logs/guoxue-v2-h20-phase23_merged_20260323/qps_0.5878/README.md`（快速结论+结果指针）
- 更新 `results/README.md`：补充 qps0.5878_analysis_REPORT.md 和 HTML 文件记录

### 🐛 遇到的问题

#### 问题 1：部署名查询无数据
- **现象**：查 `xinghan-guoxue-p72b-v12-reason-h20-tp4-base/-eagle3` 无 SGLang 指标
- **根因**：VictoriaMetrics 中的实际 label 是不带 `-base/-eagle3` 后缀的 `xinghan-guoxue-p72b-v12-reason-h20-tp4`，且指标格式是旧版 `sglang:*`（冒号），而非新版下划线
- **解决**：枚举所有 `nexus_aiinfra_cece_com_name` label 值，确认正确部署名；再通过 series API 列出该部署下所有可用指标名，确认格式

#### 问题 2：Grafana E2E P90 高于离线分析
- **现象**：Grafana 均值 170.7s vs 离线 114.9s，相差 48%
- **根因**：时间段不同（Phase 2 vs Phase 3）；Grafana 使用 5min 滑窗 histogram_quantile 而非全局精确分位数
- **解决**：在报告 §4.5 详细解释差异机理，以 Phase 3 离线分析为 SLA 判定依据

### 📊 关键数据

| 指标 | Phase 3 离线 | Grafana Phase 2 | SLA | 判定 |
|------|------------|----------------|-----|------|
| 成功率 | 99.91% | — | ≥99% | ✅ |
| TTFS P90 | 0.635s | — | ≤1500ms | ✅ |
| E2E P90 | 114.9s | 170.7s(均值) | ≤180s | ✅ |
| QPM | 34.4 | 34.2 | — | 吻合 |
| 并发 | 55.2(理论) | 56.6(实测) | — | ✅ |

---

## 2026-03-25（续）：Eagle3 4×H20 rps=0.5878 探针分析

### 📌 任务

对 `logs/eagle3-4h20-probe-rps0.5878_20260324_2037` 进行 benchmark-result-analysis，整合离线分析与 Grafana 监控（2026-03-24 20:39–21:42）。

### ✅ 实现功能

1. **离线 CDF 分析**：2117 条请求，成功 2093（98.87%），E2E P90=480.5s，生成 HTML+7 PNG
2. **Grafana 查询**：部署 `xinghan-guoxue-p72b-v12-reason-h20-tp4-eagle3`，指标格式 `sglang_*`（新版下划线）；并发全程单调上升 19→265，未达稳态；spec_accept_length=2.66
3. **根因分析**：Eagle3 max sustainable RPS = 1224/2232 = 0.548 req/s < 0.5878（超载 7.2%）
4. **报告写作**：`results/guoxue-v2-eagle3-4h20-probe-20260324/REPORT.md`，含与 Vanilla H20 完整横向对比
5. **归档**：logs README + results/README.md 新增条目

### 📊 核心指标

| 指标 | Eagle3 4×H20 | Vanilla 4×H20 | SLA |
|------|:---:|:---:|:---:|
| 成功率 | 98.87% ❌ | 99.91% ✅ | ≥99% |
| TTFS P90 | 2.197s ❌ | 0.635s ✅ | ≤1.5s |
| E2E P90 | 480.5s ❌ | 114.9s ✅ | ≤180s |
| 并发（稳态）| 184（增长中）❌ | ~57 ✅ | — |
| Max RPS | ~0.548 req/s | 0.584 req/s | — |
| spec_accept_len | 2.66 | N/A | — |

**结论：Eagle3 4×H20 在 rps=0.5878 系统过载，SLA 全面失败，需在 ≤0.548 req/s 重新探针。**

---

## 2026-03-25：会话历史批量导出（sessions 25-68）

### 📌 任务
将项目开发过程中从 session 24（2026/3/13）到 session 68（2026/3/24）之间所有未导出的 Cursor 聊天会话内容，按标准格式导出到 `clingo/sessions/` 目录，供 openclaw 角色深度优化使用。

### ✅ 实现功能

1. **系统分析**：扫描 75 个 agent transcript，通过内容匹配将已有的 sessions 01-24 对应到具体 UUID，识别 sessions 36（d8791542）和 72（849e07b1）为用户手动导出，跳过重复导出
2. **时序排序**：按 JSONL 文件修改时间对所有未导出 transcript 进行排序，编号 sessions 25-35 和 37-68
3. **批量转换**：将 44 个 transcript 的 JSONL 格式转换为标准 markdown 格式，写入 `clingo/sessions/`
4. **格式清理**：移除内容中的 `<user_query>`、`<system_reminder>`、`<git_status>` 等系统标签，保持与手动导出格式一致

### 📊 导出会话概况

| 范围 | 数量 | 日期范围 | 主要内容 |
|------|------|---------|---------|
| sessions 25-35 | 11 | 2026/3/13 - 3/17 | LLM benchmark 参数、数据集处理、git commit、skill 文档审查、batch export、lingyu 模型、工作方向规划、dashboard 设计 |
| sessions 37-68 | 32 | 2026/3/18 - 3/24 | chart-32b QPS 评估、qps-peak-finder skill 设计（session 42 核心）、chart vs guoxue 模型评估、数据处理 pipeline、eagle3 L20 QPS 分析、H20 阶段性检查、日报 |

**总计**：clingo/sessions 现有 69 个会话文件（01-68 + 手动导出的 36 和 72）

### 💡 关键会话亮点（供 openclaw 参考）

- **session 32**（36ba58c2）：sessions 01-24 批量导出的执行过程，包含项目早期全景
- **session 42**（573b4ec8）：qps-peak-finder SKILL 从讨论→设计→实现的完整过程（4255 行，234 条消息）
- **session 54**（39ef013f）：guoxue 数据处理 pipeline 深度分析（3485 行）
- **session 58/60**（e7e46ac0/d8de76d0）：大型 git commit 会话，含 skill 版本迭代全记录

---

---

## 2026-03-25（续）：两次生产端点探针分析 + 报告体系对齐梳理

### 📌 任务

1. 对 2026-03-25 新跑完的两个 rps=0.5878 探针执行 `benchmark-result-analysis`
2. 通过 brainstorming 设计并执行报告体系对齐（REPORT.md / EVAL_REPORT.md / model-context.md）

---

### ✅ 任务一：两个探针离线分析

#### Vanilla H20 infra-base 探针（`guoxue-v2-4h20-probe-rps0.5878_20260325_1140`）

- **端点**：`infra-base-xinghan-guoxue-p72b-v12-reason`（生产网关）
- **数据集**：`_all.csv`（50,000 行）
- 离线分析：成功率 100.00%，TTFT P90=0.565s，TTFS P90=0.752s，E2E P90=189.55s
- Grafana 监控：并发均值 83.6，TTFT P90=0.60s，E2E P90（5min 均值）=193.53s
- 报告：`results/guoxue-v2-4h20-probe-infra-base-20260325/REPORT.md`
- 结论：⚠️ TTFT/TTFS 达标，E2E P90 略超 SLA（189.6s vs 180s），原因为测试期间共享负载（背景流量 ~16 RPM）

#### Eagle3 infra-opti 探针（`eagle3-4h20-probe-rps0.5878_20260325_1156`）

- **端点**：`infra-opti-xinghan-guoxue-p72b-v12-reason`（Eagle3 生产端点）
- **数据集**：`_all.csv`
- 离线分析：成功率 75.15%，TTFT P90=1.420s，TTFS P90=3.315s，E2E P90=600.59s
- Grafana 监控：并发均值 256.66（峰值 338），E2E P90 均值 779.8s
- 报告：`results/guoxue-v2-eagle3-4h20-probe-infra-opti-20260325/REPORT.md`
- 结论：❌ 系统严重过载，与 2026-03-24 结论一致（**二次确认**），估算 max sustainable RPS ≈ 0.52 req/s

---

### ✅ 任务二：报告体系对齐梳理（brainstorming 方案 C + A）

#### 设计决策

- **数据治理**：新探针保持独立目录，不合并入 Phase 3，通过交叉引用连接
- **Phase 3 权威性**：infra-base 探针仅作"生产端点观测"附注，不影响 ideal_rps=0.5878 结论
- **TTFT/TTFS 口径统一**：EVAL_REPORT.md §4.3 H20 容量表纠正为 TTFT P90 + TTFS P90 分列

#### 改动的四份文件

| 文件 | 改动内容 |
|------|---------|
| `logs/.../qps_0.5878/README.md` | 补充 TTFS P90=635ms；新增"生产端点补充观测"节，含对比表 + 双向指针 |
| `results/guoxue-v2-h20-peak-finder-20260323/REPORT.md` | 新增 §5：Phase 3 直连 vs infra-base 探针完整对比，差异根因说明 |
| `results/models/.../EVAL_REPORT.md` | §4.2 拆分并发行（极限230 / 理想57）；§4.3 H20 表 TTFT/TTFS 分列修正；新增 §4.6 生产端点观测；修正 §4.6 超链接格式 |
| `results/models/.../model-context.md` | `h20_server_concurrency:46` 拆为三字段（phase1/ideal/extreme）；新增 `h20_infra_base_probe_*` 字段组（11个字段）|

---

### 🐛 遇到的问题

#### 问题 1：REPORT.md `StrReplace` 失败
- **现象**：表格行有 `||` 前缀格式，与替换字符串不匹配
- **解决**：改用 Python `content.replace()` 精确定位，并通过 `repr()` 检查实际文本内容

#### 问题 2：EVAL_REPORT.md H20 表第一次替换失败
- **现象**：表格 pipe 格式与预期有差异（首行有 `||` vs `|`）
- **解决**：用 `repr()` 打印实际内容后精确构造匹配字符串，第二次替换成功

#### 问题 3：§4.6 超链接格式遗漏
- **现象**：插入时使用了反引号代码文本而非 Markdown 超链接
- **解决**：用户指出后立即用 `StrReplace` 修正为 `[显示文本](../../../相对路径)` 格式

---

### 💡 关键技术洞察

1. **数据集差异可忽略**：`_stitched.csv`（6,358 行）vs `_all.csv`（50,000 行）的 messages 字符均值仅差 0.9%，old_response 差 0.7%，对延迟指标无实质影响
2. **infra-base E2E 超标根因**：背景流量使并发从 57 升至 83.6（+26），额外排队时间完全解释了 E2E 从 114.9s 增至 189.6s，服务能力未变
3. **Eagle3 两次失败共同规律**：Decode 吞吐低于 Vanilla（1157 vs 1260 tok/s），max sustainable RPS ≈ 0.52，低于测试速率 0.5878 约 11.5%

---

### 📊 关键数据汇总

| 指标 | Phase 3 直连（权威）| infra-base 探针 | Eagle3 探针 |
|------|--------------------|--------------------|-------------|
| 成功率 | 99.91% | 100.00% | 75.15% ❌ |
| TTFT P90 | 522ms | 565ms | 1,420ms |
| TTFS P90 | 635ms | 752ms | 3,315ms ❌ |
| E2E P90 | 114.9s ✅ | 189.6s ⚠️ | 600.6s ❌ |
| Grafana 并发均值 | ~57 | 83.6 | 256.66 |


---

## 🗓️ 2026-03-25 下午场（续）— 多端点 QPS 探针启动

### 🎯 本次目标

1. 为新的 `infra-base` 端点以正确命名目录重跑 RPS=0.5878 探针
2. 为调整后的 `infra-opti` Eagle3 4×H20 服务重跑 RPS=0.5878 探针
3. 为 2TP 部署模式新端点发起 RPS=0.3 探针（初步验证）

---

### ✅ 任务一：infra-base 端点重命名重跑（RPS=0.5878）

- **端点**：`https://infer.geniuworks.com/infra-base-xinghan-guoxue-p72b-v12-reason/v1/chat/completions`
- **原因**：首次启动日志目录命名为 `eagle3-4h20-probe-rps0.5878_20260325_1032`，与实际端点不匹配，用户要求更正
- **修正后目录**：`logs/guoxue-v2-4h20-probe-rps0.5878_20260325_1140/`
- **PID**：`1953463`
- **参数**：`--request-rate 0.5878 --num-requests 2117 --request-time-limit 3600 --no-kvcache --shuffle`
- **状态**：✅ 探路请求成功，正式打流已完成

---

### ✅ 任务二：Eagle3 infra-opti 调整后重跑（RPS=0.5878）

- **端点**：`https://infer.geniuworks.com/infra-opti-xinghan-guoxue-p72b-v12-reason/v1/chat/completions`
- **背景**：用户对 Eagle3 4×H20 服务做了调整，希望重新验证
- **第一次尝试**（PID `1958187`，目录 `eagle3-4h20-probe-rps0.5878_20260325_1145`）：
  - 运行约 5 分钟后，用户观察服务端日志异常，**主动 kill**
- **第二次启动**（服务调整完成后）：
  - PID：`1966237`
  - 目录：`logs/eagle3-4h20-probe-rps0.5878_20260325_1156/`
  - 探路请求成功，正式打流已完成

---

### ✅ 任务三：2TP 部署模式 RPS=0.3 探针

- **端点**：`https://infer.geniuworks.com/infra-opti-xinghan-guoxue-p72b-v12-reason/v1/chat/completions`
- **部署变化**：用户将该端点切换为 2TP 部署方式
- **目的**：用户希望验证 2TP 模式下 RPS=0.3 是否符合预期
- **PID**：`2075568`
- **目录**：`logs/eagle3-2tp-probe-rps0.3_20260325_1422/`
- **参数**：`--request-rate 0.3 --num-requests 1080 --request-time-limit 3600 --no-kvcache --shuffle`
- **状态**：✅ 探路请求成功，正式打流已启动（运行中）

---

### 🐛 遇到的问题

#### 问题 1：日志目录命名不规范
- **现象**：首次启动 `infra-base` 端点时，日志目录沿用了 `eagle3-4h20-probe-rps0.5878_*` 命名，与实际端点（vanilla H20）不匹配
- **解决**：首次进程已自然结束，以 `guoxue-v2-4h20-probe-rps0.5878_*` 重新启动

#### 问题 2：Eagle3 服务端配置异常
- **现象**：第一次重启 Eagle3 探针约 5 分钟后，用户观察服务端日志发现结果不正确
- **解决**：kill PID 1958187，等待用户调整服务端配置后重新启动（PID 1966237）

---

### 📊 本次会话启动的探针汇总

| 编号 | 端点 | 部署 | RPS | 请求数 | PID | 日志目录 | 状态 |
|------|------|------|-----|--------|-----|---------|------|
| 1 | infra-base（vanilla H20） | 4TP | 0.5878 | 2117 | 1953463 | `guoxue-v2-4h20-probe-rps0.5878_20260325_1140` | ✅ 完成 |
| 2a | infra-opti（Eagle3 4H20） | 4TP | 0.5878 | 2117 | 1958187 | `eagle3-4h20-probe-rps0.5878_20260325_1145` | ❌ 提前终止 |
| 2b | infra-opti（Eagle3 4H20，调整后）| 4TP | 0.5878 | 2117 | 1966237 | `eagle3-4h20-probe-rps0.5878_20260325_1156` | ✅ 完成 |
| 3 | infra-opti（Eagle3 2TP） | 2TP | 0.3 | 1080 | 2075568 | `eagle3-2tp-probe-rps0.3_20260325_1422` | 🔄 运行中 |

---

## 📋 会话记录 — 2026-03-25（工程整理：Skill 更新 + logs 目录层级化）

### ✅ 实现的功能

#### 1. Skill 数据路径对齐检查（`traffic-dataset-prep` 等）

- 检查了 `traffic-dataset-prep`、`llm-replay-benchmark`、`qps-benchmark-sweep`、`qps-peak-finder` 四个 skill 是否需要因 `datas/` → `used4evaluation/` 数据迁移而更新路径
- **结论**：`datas/output_*/` 已全部软链接，对 skill 和 benchmark 脚本透明，路径无需修改
- **唯一补充**：`traffic-dataset-prep` 的 `.env` 参数表中缺少 `agent_converted` 格式说明，已补入 `clingo/docs/skills/` 版本（`.cursor/skills/` 早已有此内容；两处是同一 inode 硬链接，同步自动完成）

#### 2. `logs/` 目录层级化改造

**新增模型父目录**：
```
logs/xinghan-chart-32b-v1-1-agent/     ← 空，等 chart benchmark 结束后手动迁入
logs/xinghan-guoxue-72b-v1-2-reason/   ← 25 个目录已迁入
logs/xinghan-ziwei-32b-v1-1/           ← 6 个目录已迁入
logs/tianji-querysafety-4b-v2-3/       ← 5 个目录已迁入
logs/lingyu-235b-A22b-v9-2/            ← 1 个目录已迁入
```

**保持共享层不变**：
- `logs/data-pipeline/`：nohup 控制台日志，共享，不加模型前缀
- `logs/archive/`：旧实验归档，共享，暂不动

**chart-32b-agent 待迁移**（当前仍在跑 Phase 1~3）：
```bash
# benchmark 结束后执行
mv chart-32b-agent-* peak_finder_chart_agent_*.log xinghan-chart-32b-v1-1-agent/
```

#### 3. 6 个 Skill 路径模板统一更新

将所有 skill 中的实验目录路径从 `logs/<exp>/` 更新为 `logs/<model-full-name>/<exp>/`：

| Skill | 更新点 |
|-------|--------|
| `qps-peak-finder` | Phase 1 / Phase 3 `OUTPUT_DIR` + 变量命名注释（`MODEL_NAME` vs `MODEL`）|
| `qps-peak-finder-analysis` | 合并目录 `MERGED` 路径 + YAML config `dir` 字段示例 |
| `qps-benchmark-sweep` | 监控命令路径 + 合并目录命名约定 + README 写入路径 + 历史案例更新 |
| `llm-replay-benchmark` | `OUTDIR` 变量 + console log 改写入 `data-pipeline/` + README 写入路径 |
| `benchmark-result-analysis` | 前置条件 CSV 路径 + `--csv` 示例 + `compare_analysis.py` 示例 |
| `model-evaluation-workflow` | skip 检查 glob 路径 + 实验 README 写入路径 + archive 注意事项 |

**变量约定（已写入 skill 注释）**：
- `MODEL_NAME` = 算法提供的完整模型名（如 `xinghan-guoxue-72b-v1-2-reason`）→ `logs/` 第一层子目录
- `MODEL` = 实验命名用短名（如 `guoxue-v2`）→ 保留在实验目录名中

---

### 🐛 遇到的问题

#### 问题 1：`StrReplace` 在 `benchmark-result-analysis` 中失败
- **现象**：文件含多字节 UTF-8 字符，工具 fuzzy match 找到错误位置
- **解决**：改用 `sed -i` 直接替换，绕过 fuzzy match 歧义

#### 问题 2：`.cursor/skills/` 与 `clingo/docs/skills/` 是否需要手动同步
- **现象**：以为是独立文件，准备 `cp` 覆盖
- **解决**：确认两处是同一 inode 硬链接，修改一处自动全局生效，无需手动同步

---

### 💡 关键技术决策

1. **logs/ 层级只加一层**：`logs/<model-full-name>/` 作为唯一新增层，实验目录短名不变，脚本改动最小
2. **共享层不加模型前缀**：`data-pipeline/`（nohup 日志）和 `archive/`（旧实验）保持在 `logs/` 根层，多模型共用
3. **向前兼容**：历史实验已物理迁移（`mv`），不用软链接，保持目录结构简洁；chart-32b-agent 当前进行中，等完成后手动迁入

---

### ⚠️ 未完成事项

- `logs/xinghan-chart-32b-v1-1-agent/` 目前为空，chart-32b-agent benchmark（Phase 1~3）结束后需手动执行迁移命令
- `logs/archive/` 内旧数据（chart/guoxue/tianji 混排）未整理，可按需后续处理

---

## 2026-03-25 下午场 — chart-32b-agent 4TP/8TP QPS Peak Finder Phase 1 完成 + Phase 2 启动

### ✅ 实现的功能

#### 1. 排查 run_phase1_saturation.sh 语法错误根因
- **现象**：`run_phase1_saturation.sh: line 175: unexpected EOF while looking for matching '"'`，exit code 2，Phase 1 中止
- **根因**：Bash 以增量方式读取脚本文件（非一次性全量读入）。con=400 benchmark 跑了 20 分钟，期间 Cursor 对 `run_phase1_saturation.sh` 进行了修改（新增 Python 推算 `NUM_REQUESTS` 的代码块）。Python 进程结束后 bash 继续读文件时，读到了正在写入的中间状态——新增的多行 `$(python3 -c "...")` 双引号字符串未闭合，触发 EOF 错误
- **结论**：文件本身语法无误（`bash -n` 验证通过），只需重跑即可；避免在脚本运行期间编辑该文件

#### 2. 分析 8TP Phase 1 全部档位结果（已完成饱和）

| 并发 | decode_throughput | 增幅 |
|------|-------------------|------|
| con=50 | 1211.0 t/s | — |
| con=100 | 1706.0 t/s | +40.87% |
| con=200 | 1955.4 t/s | +14.62% |
| con=400 | **2056.8 t/s** | +5.18% → 接近饱和，步进+10 |
| con=410 | 2055.9 t/s | **-0.04% → ✅ 已饱和** |

- **8TP 结论**：峰值 con=400，peak_decode_throughput=2056.8 t/s
- max_rps（Phase 0 avg=452）= 2056.8/452 = **4.55 req/s**，Phase 2 START_RPS = **5.46 req/s**

#### 3. 补跑 4TP Phase 1 con=480，确认饱和

| 并发 | decode_throughput | 增幅 |
|------|-------------------|------|
| con=25→200 | （见前日记录） | — |
| con=400 | **1627.7 t/s** | +10.66% → 未饱和，分段×1.2 |
| con=480 | 1567.3 t/s | **-3.71% → ✅ 已饱和** |

- **4TP 结论**：峰值 con=400，peak_decode_throughput=1627.7 t/s
- max_rps（Phase 0 avg=452）= 1627.7/452 = **3.60 req/s**，Phase 2 START_RPS = **4.32 req/s**
- 4TP/8TP 吞吐比 ≈ 1627/2057 ≈ **0.79**，远低于理论 2x，说明 8 卡 TP 通信开销显著

#### 4. 修复 7 个 chart agent 脚本路径（logs 迁移适配）
用户将 `logs/chart-32b-agent-*` 物理移动到 `logs/xinghan-chart-32b-v1-1-agent/`，修复以下脚本的 OUTPUT_BASE/SESSION_DIR 硬编码路径：
- `run_peak_finder_chart_agent.sh`
- `run_phase1_auto_chart_agent_4tp.sh` / `_8tp.sh`
- `run_phase2_auto_chart_agent_4tp.sh` / `_8tp.sh`
- `run_phase3_grid_chart_agent_4tp.sh` / `_8tp.sh`

修改模式：`logs/chart-32b-agent-*` → `logs/xinghan-chart-32b-v1-1-agent/chart-32b-agent-*`

#### 5. 修复 analyze_peak_finder.py 的 checkpoint 写入 bug
- **Bug**：`_write_phase1_checkpoint()` 函数签名只有 8 个参数，但调用时传入了 9 个（`avg_output_len_phase0` 和 `avg_output_len_measured` 分别传入，而签名只有一个 `avg_output_len`）
- **修复**：将函数签名拆分为两个参数，checkpoint 表格同时记录 Phase 0 权威值和 Phase 1 实测值，符合 SKILL 规范

#### 6. 启动 8TP Phase 2（18:19）
- PEAK_RPS=4.5493，START_RPS=5.4592
- 命令：`START_PHASE=2 PEAK_RPS=4.5493 START_RPS=5.4592 bash scripts/benchmark/run_peak_finder_chart_agent.sh 8tp`
- 进程 pid: 2266194/2266206/2266248，日志：`logs/data-pipeline/peak_finder_chart_agent_8tp_console.log`
- 输出目录：`logs/xinghan-chart-32b-v1-1-agent/chart-32b-agent-8tp-phase2_20260325_1819/`

#### 7. 启动 4TP Phase 2（19:00）
- PEAK_RPS=3.6010，START_RPS=4.3212
- 命令：`START_PHASE=2 PEAK_RPS=3.6010 START_RPS=4.3212 bash scripts/benchmark/run_peak_finder_chart_agent.sh 4tp`
- 进程 pid: 2301413/2301419/2301470/2301480，日志：`logs/data-pipeline/peak_finder_chart_agent_4tp_console.log`
- 输出目录：`logs/xinghan-chart-32b-v1-1-agent/chart-32b-agent-4tp-phase2_20260325_1900/`

---

## 📅 2026-03-25 下午场（第二轮）— analyze_peak_finder.py 全面加固

**会话目标**：修复上一轮遗留的 5 个 Phase 0/Phase 1 分析逻辑问题，并补全调用链

---

### ✅ 完成的工作

#### 1. Phase 0：500 条采样 → 全量 tokenize

- **修改文件**：`scripts/analysis/analyze_peak_finder.py`（`analyze_dataset()` 函数）
- **变更**：删除 `head(500)` 采样，改为对全量 `valid` 行执行 tokenize，加入进度提示
- **意义**：采样偏差可高达 20%+ 对大数据集（5~50K 条），全量才是权威 Phase 0 值

#### 2. Phase 0：添加数据质量检查（think 比例 / con 残留）

- **修改文件**：`scripts/analysis/analyze_peak_finder.py`
- **新增逻辑**：
  - `<think>` 比例检查：推理模型应 ≥ 70%，否则打 ⚠️ 警告
  - `<con>` 残留检查：应 < 5%，否则提示模型版本格式可能已变更
  - 最终汇总输出 `数据质量: 可信 / 有缺陷`，与 SKILL.md 两步判断规则对齐
- **意义**：防止脏数据（如缺少推理链的 old_response）导致 Phase 0 值严重低估

#### 3. Phase 0：自动推算 DURATION_SECS / COOLDOWN_SECS

- **修改文件**：`scripts/analysis/analyze_peak_finder.py`
- **新增输出**：
  ```
  DURATION_SECS = max(300,  int(avg_tokens×2.5))   # Phase 1
  DURATION_SECS = max(1200, DURATION_SECS)          # Phase 2/3
  COOLDOWN_SECS = max(60,   int(avg_tokens/2))
  INIT_CON = <分段建议>
  ```
- **汇总复制块**：一键输出 `AVG_OUTPUT_LEN / TIME_LIMIT_SECS / COOLDOWN_SECS / INIT_CON` 供直接粘贴到脚本

#### 4. Phase 1：max_rps 改用 Phase 0 权威值（--avg-output-len-phase0 参数）

- **修改文件**：`scripts/analysis/analyze_peak_finder.py`
- **新增 CLI 参数**：`--avg-output-len-phase0 <float>`
- **逻辑**：
  - 若提供 `--avg-output-len-phase0`：使用 Phase 0 值作为 max_rps 分母，打印两值对比
  - 若未提供：回落到 Phase 1 实测值，打 ⚠️ 提示（"存在截断偏差"）
- **意义**：Phase 1 饱和档下长请求超时丢弃，实测均值系统性偏低；Phase 0 全量统计无截断偏差

#### 5. Phase 1：checkpoint 格式增加 Phase 0/Phase 1 双值对比

- **修改文件**：`scripts/analysis/analyze_peak_finder.py`（`_write_phase1_checkpoint()`）
- **新增字段**：
  - `avg_output_len (Phase 0 权威)` 行
  - `Phase 0 vs Phase 1 偏差` 行（含 ✅/⚠️ 自动判断）
  - `avg_output_len (用于计算)` 行（说明实际分母来源）
- **函数签名**更新：`avg_output_len` 拆为 `avg_output_len_phase0` + `avg_output_len_measured`

#### 6. SKILL.md 更新

- **修改文件**：`clingo/docs/skills/qps-peak-finder/SKILL.md`
- **新增**：「Phase 1 结果分析（CLI）」节，展示 `--avg-output-len-phase0` 完整调用方式
- **更新**：Phase 1 checkpoint 格式模板，增加 Phase 0/Phase 1 双值 + 偏差行

#### 7. 全部 Phase 1 auto 脚本补传 --avg-output-len-phase0

- **背景**：前 5 个修复完成后发现调用链断裂——10 个 auto 脚本都没有把 `AVG_OUTPUT_LEN` 传给 `analyze_peak_finder.py`，新参数完全无法触发
- **修改的脚本（共 10 个）**：
  | 脚本 | AVG_OUTPUT_LEN 值 | 变更 |
  |------|-----------------|------|
  | `run_phase1_auto_chart4tp.sh` | 200 | 加 `--avg-output-len-phase0 "${AVG_OUTPUT_LEN}"` |
  | `run_phase1_auto_chart8tp.sh` | 200 | 同上 |
  | `run_phase1_auto_chart_agent_4tp.sh` | 452 | 同上 |
  | `run_phase1_auto_chart_agent_8tp.sh` | 452 | 同上 |
  | `run_phase1_auto_tianji4tp_bakv1.sh` | 14 | 同上 |
  | `run_phase1_auto_ziwei8tp.sh` | 180 | 同上 |
  | `run_phase1_auto_guoxue8tp_v2.sh` | 2157 | 加参数（不同调用结构） |
  | `run_phase1_auto_guoxue_eagle3.sh` | 2142 | 同上 |
  | `run_phase1_auto_guoxue_eagle3_4h20.sh` | 2204（`AVG_OUTPUT_LEN_PHASE0`）| 加 `--avg-output-len-phase0 "${AVG_OUTPUT_LEN_PHASE0}"` |
  | `run_phase1_auto_guoxue4h20.sh` | **新增**变量 `AVG_OUTPUT_LEN=2204` | 补变量 + 加参数 |

---

### 🐛 遇到的问题与解决

#### 问题 1：Bash 增量读取脚本导致 EOF 语法错误
- **复现条件**：脚本执行期间（外部进程跑 20min）文件被修改
- **解决**：重新手动执行单档 saturation，复用已有结果目录，不重跑已完成档位

#### 问题 2：Shell tool spawn: Aborted
- **现象**：`block_until_ms: 0` 后台命令 spawn 失败
- **解决**：改用 `nohup bash /tmp/wrapper.sh > log 2>&1 &` 方式启动长时任务

#### 问题 3：相对路径导致数据集找不到
- **现象**：`DATASET_PATH="datas/..."` 在 saturation 脚本内部 `cd ${LLM_BENCHMARK_ROOT}` 后路径失效
- **解决**：wrapper 脚本中改用绝对路径 `/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/...`

#### 问题 4：`_write_phase1_checkpoint()` TypeError
- **现象**：分析脚本报 `takes 8 positional arguments but 9 were given`，checkpoint 写入失败
- **解决**：更新函数签名，分析后补写 con=400 和 con=480 两档 checkpoint

---

### ⚠️ 未完成事项

- **4TP Phase 2 运行中**（pid 2301413），预计每档 30min，完成后自动进入 Phase 3
- **8TP Phase 2 运行中**（pid 2266194），首档 rps=5.4592，完成后自动进入 Phase 3
- Phase 2/3 完成后需运行 `qps-peak-finder-analysis` Skill 生成最终 REPORT.md

---

## 2026-03-26 — chart-32b-agent V2 分析报告生成

### 实现功能

**1. Phase 3 脚本 Bug 修复**
- 定位问题：`run_phase3_grid_chart_agent_4tp.sh` 和 `run_phase3_grid_chart_agent_8tp.sh` 在每次 qps 档位运行后，错误地将个别 qps 子目录（如 `qps1.9670/`）作为 `--dir` 传给 Phase 3 汇总分析脚本（期望的是父目录）
- 修复方案：循环内改用 `--phase 2` 做单档快速预览；在循环结束后添加 `--phase 3 --dir "${OUTPUT_BASE}"` 的完整汇总调用
- 文件：`scripts/benchmark/run_phase3_grid_chart_agent_4tp.sh` / `run_phase3_grid_chart_agent_8tp.sh`

**2. Little's Law 服务端并发估算**
- 4TP（con400 峰值档）：max_rps=3.4279，mean_e2e=103.04s → **server_concurrency ≈ 353**
- 8TP（con400 峰值档）：max_rps=4.3401，mean_e2e=83.76s → **server_concurrency ≈ 364**

**3. Phase 2+3 数据合并**
- 4TP：`chart-32b-agent-4tp-phase23_merged_20260326/`（10档：6×Phase2 + 4×Phase3）
- 8TP：`chart-32b-agent-8tp-phase23_merged_20260326/`（10档：6×Phase2 + 4×Phase3）

**4. 容量曲线图表生成**
- YAML：`configs/models/xinghan-chart-32b-v1-1-agent/peak_finder_analysis_20260325.yaml`
- 成功分析 18/20 个档位（2个轻微加载问题，不影响结论）
- 输出：`results/chart_agent_tp_compare_20260325/plot_latency_2d.html` 等 3 个图表

**5. REPORT.md 生成**（`results/chart_agent_tp_compare_20260325/REPORT.md`）
- §0 三锚点摘要（极限/理想/生产 RPM）
- §1-§3 三阶段详细数据
- §6 8TP vs 4TP 对比结论
- §7 上线建议

**6. 归档更新**
- `results/models/INDEX.yaml`：更新 chart-32b-agent 条目，eval_status 改为 completed_v2
- `results/README.md`：新增 chart_agent_tp_compare_20260325 条目

### 关键结论（V2 最终）

| 配置 | 理想 RPS | 理想 RPM | TTFS P90@SLA边界 |
|------|---------|---------|----------------|
| 4TP（infra-opti） | 2.2175 req/s | 133 RPM | 1,488ms（裕量 0.8%）|
| 8TP（infra） | 3.8286 req/s | 230 RPM | 1,443ms（裕量 3.8%）|
| 8TP/4TP 倍率 | **1.73×** | — | — |

- 生产负载（118 RPM）：4TP TTFS=1415ms（裕量仅 5.7%），8TP TTFS=790ms（裕量充足）
- V2 数据集（Agent 全量）导致 QPS 比 V1 低约 50%，原因是 Agent 工具调用序列延长了 avg_output_len

### 遇到的问题及解决

- **Phase 3 汇总报错 "下未找到 qps_X.XXXX 子目录"**：脚本 Bug，传参错误，已修复
- **图表工具路径问题**：`--config` 中 dir 需使用绝对路径，已更新 YAML
- **18/20 分析成功**：2个 Phase3 csv 轻微加载警告，不影响整体结论

---

## 2026-03-26 下午 — chart-32b-v1-1-agent 8TP 回放压测（Agent V2 数据，118 RPM）

### 实现的功能

**1. 回放日志目录整理**

将自动执行脚本生成的 `logs/chart-32b-8tp_replay_20260326_122515/` 移动至正确归档路径：  
`logs/xinghan-chart-32b-v1-1-agent/chart-32b-8tp_replay_20260326_122515/`

**2. 离线分析（benchmark-result-analysis Skill）**

运行 `offline_analysis.py` 处理 721MB 结果 CSV（5,779 条）：

| 指标 | 值 |
|------|-----|
| 成功率 | **100.00%** |
| TTFT P90 | **0.207 s**（SLA ≤1.5s，裕量 86%）|
| TTFS P90 | **0.518 s**（SLA ≤1.5s，裕量 65%）|
| E2E P90 | **14.034 s**（SLA ≤150s，裕量 91%）|
| Decode 吞吐 | 472.5 tokens/s |

**3. 结果归档**

- `results/chart_agent_8tp_replay_20260326/REPORT.md`（完整分析报告）
- 7 张 PNG 图表（ttft_cdf/ttfs_cdf/e2e_cdf/itl_cdf/user_tpot_cdf/concurrency_timeline/success_rate_timeline）
- `results/README.md` 新增条目
- `results/models/INDEX.yaml` 追加回放指标字段
- logs README 更新结论与结果指针

### 遇到的问题及解决

- 无异常，回放全程 0 失败，成功率 100%

### 结论

8TP 在使用真实 Agent 调用数据（含完整占星 system prompt）、118 RPM 生产峰值下回放，所有 SLA 指标大幅达标，可安全支撑当前生产流量及短期内业务增长至约 200 RPM 量级。

---

## 2026-03-26 下午场：Eagle3 4×H20 调参后探针测试

### 背景

基于 [TurboSpec 论文](https://arxiv.org/html/2406.14066v3) §4.1.2 **Understanding Goodput** 的研究结论：

> 在接受率较低时（本场景接受率 ≈ 0.67），应减少投机 token 数量，以避免过多的 rejected token 浪费计算资源。较短的 proposal 在中等接受率下能带来更高的 goodput。

用户据此将服务端 Eagle3 参数调整：
- **调整前**：`--speculative-num-steps 3 --speculative-eagle-topk 1 --speculative-num-draft-tokens 4`
- **调整后**：`--speculative-num-steps 2 --speculative-eagle-topk 1 --speculative-num-draft-tokens 3`

### 实现功能

1. **新建探针脚本** `scripts/benchmark/run_guoxue_eagle3_4h20_probe_tuned.sh`
   - 与前次探针（2026-03-25 11:56）参数完全一致（RPS=0.5878，duration=3600s，num_requests=2117）
   - 端点：`infra-opti-xinghan-guoxue-p72b-v12-reason`（Eagle3 4×H20）
   - 仅服务端 speculative 参数变化，方便对比

2. **后台启动探针测试**
   - 开始时间：2026-03-26 18:46:40
   - PID：3384463
   - 日志：`logs/data-pipeline/eagle3-4h20-probe-tuned-rps0.5878_20260326_1846.log`
   - 输出目录：`logs/xinghan-guoxue-72b-v1-2-reason/eagle3-4h20-probe-tuned-rps0.5878_20260326_1846/`

### 遇到的问题及解决

- 无异常，服务冒烟测试 HTTP 200，任务正常启动

### 预计完成

约 1 小时后（19:46），届时需运行 `analyze_peak_finder.py` + `offline_analysis.py` 分析结果。

### 对比基准

| 维度 | 旧探针（20260325_1156） | 新探针（20260326_1846） |
|------|----------------------|----------------------|
| speculative steps | 3 | **2** |
| draft tokens | 4 | **3** |
| 接受率 | ~0.67 | ~0.67（相同服务数据） |
| RPS | 0.5878 | 0.5878 |
| 旧结论 | ❌ 成功率 75.15%，E2E P90=600s，严重过载 | 待观测 |

---

## 2026-03-26 晚间场：chart-deep-v5-2-235B 8×H20 QPS 评估 Phase 1 完成 + relay 修复 + Phase 2 启动

### 背景

承接上午场已启动的 chart-deep-v5-2-235B 8×H20 QPS 评估流程（Phase 1 于 11:49 启动），本场处理 Phase 1 完成后的接力问题，修复 relay 脚本 bug，完成 Phase 2 干净启动。

### 实现功能

#### 1. Phase 1 完成确认

Phase 1（`run_phase1_auto_chart_deep_8h20.sh`）于 14:28 完成，共跑 3 个并发档位：

| 档位 | 完成时间 | decode_throughput | max_rps_estimate | 吞吐增幅 |
|------|---------|-------------------|-----------------|---------|
| con=60 | 12:35 | 976.606 tok/s | 0.9708 req/s | — |
| con=120 | 13:31 | 1287.415 tok/s | 1.2797 req/s | +31.83% |
| con=180 | 14:28 | 1298.889 tok/s | **1.2911 req/s** | +0.89% ✅ 已饱和 |

- **PEAK_RPS = 1.2911 req/s**，Phase 2 起始 START_RPS = 1.5493 req/s（× 1.2）
- checkpoint 文件：`logs/chart-deep-v5-2/chart-deep-v5-2-phase1_20260326_1149/phase1_checkpoint.md`

#### 2. 修复 `watch_and_relay_chart_deep_8h20.sh` 两个 Bug

**Bug 1（提前退出）**：
- 原因：relay 的 Phase 1 等待循环在 checkpoint 文件一出现（con=60 结束后写入）就 `break`，而此时 Phase 1 仍在继续跑 con=120、con=180
- 修复：在循环内增加二次判断，检查 Phase 1 run log 是否包含 `"Phase 1 全部档位完成"` 或 `NEXT_CON=SATURATED`，只有确认完成才 break

**Bug 2（PEAK_RPS 解析失败导致 set -e 退出）**：
- 原因：checkpoint 是 Markdown 表格格式 `| max_rps_estimate | 0.9708 req/s |`，而 grep 用的是 `max_rps_estimate\s*=\s*\K` 格式，无法匹配，grep 返回 exit code 1，触发 `set -euo pipefail` 退出
- 修复：改为 `grep -oP '\|\s*max_rps_estimate\s*\|\s*\K[0-9]+\.[0-9]+'` + `|| true`，并取 `tail -1` 获取最后档位值（最高并发的估算值）

#### 3. 清理重复 Phase 2 进程

由于多次调试，出现了 2~3 个 Phase 2 进程同时向同一服务器发请求（各自都在 rps=1.5493），导致实际负载翻倍，测量结果不可信。完整清理步骤：
1. 杀掉所有 Phase 2 进程（PID: 3197682/3197713、3199504/3199524、3203943/3204003）
2. 删除两个污染目录：`chart-deep-v5-2-phase2_20260326_1434`、`chart-deep-v5-2-phase2_20260326_1436`
3. 删除对应 log：`phase2_run_20260326_1434.log`、`phase2_run_20260326_1436.log`

#### 4. 干净启动 Phase 2 + Relay（14:41）

- Phase 2 脚本：`run_phase2_auto_chart_deep_8h20.sh`，`PEAK_RPS=1.2911 START_RPS=1.5493 PRODUCTION_RPS=0.5`
- 输出目录：`logs/chart-deep-v5-2/chart-deep-v5-2-phase2_20260326_1441/`
- Relay 日志：`logs/chart-deep-v5-2/relay_20260326_1441.log`（PID 3204623）
- 监控命令：`tail -f logs/chart-deep-v5-2/relay_20260326_1441.log`

#### 5. Phase 2 进展（截至本日志写入时，20:18）

- 已完成 rps=1.5493（预期违 SLA），上界压缩
- 正在跑 rps=1.3582（第二档，bracket 二分中点）

### 遇到的错误及解决

| 错误 | 原因 | 解决 |
|------|------|------|
| relay 12:36 就退出，Phase 2 从未启动 | Bug 1 + Bug 2（见上） | 修复 relay 脚本，重新启动 |
| 两个 Phase 2 同时跑，数据污染 | 手动启动 Phase 2 后又启动 relay（relay 会再启动一次 Phase 2） | 原则：relay 管理 Phase 2，**不应手动启动 Phase 2** |
| `Command failed to spawn: Aborted` | Cursor shell 执行 kill 命令偶发失败 | 重试，或直接在服务器终端执行 |

### 当前状态（20:18）

| 进程 | PID | 状态 |
|------|-----|------|
| Phase 2 bash 脚本 | 3204661 | ✅ 运行中 |
| Phase 2 Python benchmark | 3204676 | ✅ 运行中（rps=1.3582） |
| Relay 接力监控 | 3204623 | ✅ 运行中 |

### 预计后续时间线

| 节点 | 预计时间 |
|------|---------|
| Phase 2 完成（5～8 轮收敛） | 约 19:00～21:00（已在进行中） |
| Phase 3 自动触发（4 点网格） | Phase 2 完成后自动，约 +3.3h |
| 全流程完成 | 约 22:00～次日 00:00 |

---

## 📅 2026-03-27 会话记录

### 📌 本次会话主要目标

发现并修复旧跑受服务端 `--max-running-requests 128` 限制导致的"假饱和"与"假失败"问题；重跑 Phase 1（从 con=180）+ Phase 2（无限制），获取真实性能边界。

---

### ✅ 实现了哪些功能

#### 1. 🔍 问题诊断与根因分析

**发现旧跑全链路受 128 并发上限污染**：

| 阶段 | 档位 | 污染方式 | 影响 |
|------|------|---------|------|
| Phase 1 旧跑 | con=180 | max_active 被限制在 128，吞吐提升只有 0.89% | 假性饱和，max_rps_estimate 低估 23% |
| Phase 2 旧跑 | rps=1.3582 | max_active=137 > 128，服务端排队 TTFS P90 飙升至 4125ms | 假性 FAIL，bracket 被人为截断 |
| Phase 2 旧跑 | ideal_rps=1.3360 | max_active=131 轻超 128，TTFS 裕量仅 8.5% | ideal_rps 偏保守下界 |
| Phase 3 旧跑 | 全档 | 基于假 ideal_rps=1.3360 构建网格 | 结果形态参考有效，绝对值偏低 |

#### 2. 🔧 三个脚本修复（Phase 1/2/3 全链路）

**修复内容**：

| 脚本 | 问题 | 修复方式 |
|------|------|---------|
| `run_phase1_auto_chart_deep_8h20.sh` | SERVER_URL 为旧 IP `172.21.65.228` | 更新为 `172.21.65.249` |
| `run_phase1_auto_chart_deep_8h20.sh` | `MAX_REQUESTS=5621` 硬编码（实为 con=60 估算值，高并发档会导致数据集提前耗尽） | 删除 `MAX_REQUESTS=5621`，改为脚本动态计算（数据集实有 288,595 行） |
| `run_phase1_auto_chart_deep_8h20.sh` | `PREV_DIR` 初始值为空，con=180 续跑时无旧 con=120 基准 | 改为 `PREV_DIR="${PREV_DIR:-}"` 支持环境变量注入旧目录路径 |
| `run_phase1_auto_chart_deep_8h20.sh` | AUTO_PHASE2 触发 Phase 2 时未透传 `INIT_LO` | 补充 `INIT_LO="${INIT_LO:-}"` 环境变量透传，让 Phase 2 从旧 PASS 值起建 bracket |
| `run_phase2_auto_chart_deep_8h20.sh` | SERVER_URL 为旧 IP | 更新为 `172.21.65.249` |
| `run_phase3_grid_chart_deep_8h20.sh` | SERVER_URL 为旧 IP | 更新为 `172.21.65.249` |

#### 3. 🚀 Phase 1 新跑（2026-03-27 12:47 启动）

启动命令：
```bash
INIT_CON=180 \
PREV_DIR="logs/chart-deep-v5-2/chart-deep-v5-2-phase1_20260326_1149/con120" \
AUTO_PHASE2=1 \
INIT_LO=1.3360 \
nohup bash scripts/benchmark/run_phase1_auto_chart_deep_8h20.sh \
    > logs/chart-deep-v5-2/phase1_run_20260327_1247.log 2>&1 &
```

**完整 Phase 1 数据对比**：

| 档位 | decode (tok/s) | 增幅 | max_active | 备注 |
|------|---------------|------|-----------|------|
| con=120（旧，参考） | 1287.4 | — | 120 | 旧跑可信基准 |
| con=180（新） | 1429.1 | **+11.01%** | 180 | 去限制后立即显著提升 |
| con=270（新） | 1502.2 | +5.11% | 270 | — |
| con=283（新） | 1543.9 | +2.77% | 283 | — |
| con=297（新） | 1560.0 | +1.04% | 297 | 接近饱和 |
| con=311（新） | ~1597.5 | ~+2.4% | 311 | — |
| **con=326（新）** | **1603.6** | **+0.38% ✅ 饱和** | 326 | 饱和确认 |

**关键结论**：
- `peak_decode_throughput = 1603.6 tok/s`
- `max_rps_estimate = 1.5940 req/s`（旧值 1.2911，**提升 +23.5%**）
- 真实饱和并发 = 326（旧限制截断在 128）
- Phase 2 `START_RPS = 1.5940 × 1.2 = 1.9128 req/s`（实际因 INIT_LO=1.3360 从 1.4696 起探）

#### 4. 🔄 Phase 2 新跑（2026-03-27 18:57 自动启动）

- 输出目录：`logs/chart-deep-v5-2/chart-deep-v5-2-phase2_20260327_1857/`
- INIT_LO=1.3360（旧 PASS，新服务大概率仍 PASS）
- 未设 INIT_HI（旧 1.3582 的 FAIL 不可信）
- 第一档：`rps=1.3360 × 1.1 = 1.4696`，**FAIL**（TTFS P90=1838ms，超标 23%）
- 当前状态：bracket LO=1.3360, HI=1.4696，宽度 10%，下一档 `√(1.3360×1.4696) = 1.4012`
- 正在冷却 510s 后探 rps=1.4012

#### 5. 📊 rps=1.3360 档位离线分析

**目录**：`results/chart-deep-v5-2-phase2-rps1.3360-20260326/`

核心产出：
- `chart_deep_phase2_rps1.3360_analysis.html`（交互式 HTML，1720KB）
- 7 张 PNG 图表（TTFT/TTFS/E2E/ITL CDF，并发时间线，成功率时间线）
- `REPORT.md`（含完整分析，128 限制指纹解读，相邻档位对比表）

关键指标：
- 成功率：99.91%（3367/3367，仅 3 失败）
- TTFS P90：1382ms（裕量 8.5%，TTFT P99=1327ms 有长尾跳升，128 排队信号）
- E2E P90：109.1s（裕量 27%）
- Decode：1302.9 tok/s

#### 6. 📝 中间分析报告生成

- `results/models/chart-deep-v5-2-235B/model-context.md`（模型配置、数据背景、阶段性结论）
- `results/models/chart-deep-v5-2-235B/EVAL_REPORT_interim.md`（中间评估报告，含旧/新跑对比、关键发现、128 限制量化影响分析）

---

### 🐛 遇到的错误及解决

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| Shell `Command failed to spawn: Aborted` | Cursor 内置 shell 不支持某些 nohup 复杂写法 | 简化为单行 nohup 命令，环境变量前置传入 |
| Phase 1 旧跑于 con=180 假性饱和 | 服务端 `--max-running-requests 128`，con=180 时内部实际并发被卡在 128 | 新服务已去限制，从 con=180 重跑 |
| Phase 2 旧跑 rps=1.3582 假性 FAIL | max_active=137>128，排队导致 TTFS P90 飙升至 4125ms | 新 Phase 2 不传 INIT_HI，让算法重新找真实失败点 |
| Phase 1 脚本 `MAX_REQUESTS=5621` 高并发档数据集提前耗尽 | 脚本写入时按 con=60 估算了 5621，高并发档 5621 条远不够 2520s | 删除硬编码上限，动态计算（数据集有 288,595 行） |
| Phase 2 INIT_LO 无法通过 AUTO_PHASE2 透传 | 旧脚本写法 `${INIT_LO:+INIT_LO="${INIT_LO}"}` 在 bash env 前缀位置不支持 | 改为 `INIT_LO="${INIT_LO:-}"` 统一赋值（空字符串时 Phase 2 脚本忽略） |

---

### 📊 当前进行中任务（2026-03-27 19:30 状态）

| 模型 | 阶段 | 当前档位 | 预计完成 |
|------|------|---------|---------|
| chart-deep-v5-2-235B 8×H20 | **Phase 2 新跑** | rps=1.4012（冷却后启动） | 约 21:30~22:00 |

---

### ⏭️ 下次会话需关注

1. **chart-deep Phase 2 新跑结果**：
   - 输出目录：`logs/chart-deep-v5-2/chart-deep-v5-2-phase2_20260327_1857/`
   - 日志：`logs/chart-deep-v5-2/phase1_run_20260327_1247.log`（Phase 1+2 合并日志）
   - Phase 2 收敛后自动触发 Phase 3 网格验证
   - 完成后运行 `qps-peak-finder-analysis` Skill 生成 REPORT.md

2. **业务峰值 RPM 待确认**：当前保守托底 30 RPM（0.5 req/s），实际值需从 Grafana 获取后更新 model-context.md 并重新计算实例数

3. **最终 EVAL_REPORT.md**：
   - 更新 `results/models/chart-deep-v5-2-235B/EVAL_REPORT_interim.md` → 覆盖为正式版
   - 关键预期结论：`extreme_rps≈1.5940`, `ideal_rps≈1.40~1.43 req/s`（84~86 RPM）

---

## 📅 2026-03-27 guoxue Eagle3 4×H20 多档位 SLA 边界探针

> **会话时间**：2026-03-27 16:00 — 19:00
> **主题**：guoxue-72b-v1-2-reason Eagle3 4×H20 多档位探针测试，定位 ideal_rps SLA 边界

---

### ✅ 实现了哪些功能

#### 1. Phase2 rps=0.3415 离线分析与归档
- 发现 Phase 2 实验目录中 `rps0.4519` 为空（脚本 EXIT_TRAP 提前退出，未写入数据），仅 `rps0.3415` 有完整 CSV
- 运行 `offline_analysis.py` 对 rps=0.3415 做完整分析：成功率 100%，TTFT P90=0.489s，TTFS P90=0.594s，E2E P90=44.8s，SLA 全达标
- 生成报告：`results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-phase2-20260324/REPORT.md`

#### 2. RPS=0.4 单点探针（服务参数调整后重启）
- 第一次启动 rps=0.519（20分钟）→ 用户暂停，调整服务参数
- 第二次启动 rps=0.519 → 发现与之前进程冲突，用户手动 kill 并重启服务
- 第三次启动 rps=0.4（PID 134905）→ 用户再次手动清理进程后服务重启
- 第四次重新发起 rps=0.4（PID 128109）→ 完成，成功率 100%，E2E P90=107.2s ✅
- 生成报告：`results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.400-20260327/REPORT.md`

#### 3. RPS=0.43 单点探针
- 以 0.43 req/s（516 请求，20 分钟）运行探针
- 结果：成功率 100%，但 **E2E P90=182.1s，超过 SLA 阈值 180s（超出 1.1%）**，判定 ❌ 临界超标
- 生成报告：`results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.430-20260327/REPORT.md`

#### 4. SLA 边界定位完成
- **ideal_rps = 0.40 req/s（24 RPM）** ——当前已验证最高 SLA 达标档位
- 边界区间：`0.40 < ideal_rps < 0.43 req/s`
- 更新 `results/README.md` 追加两条新实验索引

---

### 🐛 遇到的错误及解决

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| rps=0.4519 目录为空 | Phase 2 脚本在 Round 2 结束后通过 EXIT_TRAP 提前退出，0.4519 目录预创建但未执行 | 告知用户该测试点缺失，仅对 rps=0.3415 做分析 |
| 进程残留导致多次重启测试 | `kill` 命令未完全杀死所有子进程，或用户在不同会话启动了测试 | 每次启动前用 `pgrep` 检查残留进程，确认清空后再启动 |
| rps=0.43 E2E P90 超标 | RPS 超过服务容量临界点，队列开始积压，尾部延迟非线性增长 | 确认 ideal_rps=0.40 为上界，记录临界 FAIL 档位 |

---

### 📊 多档位测试汇总

| RPS | 成功率 | TTFT P90 | TTFS P90 | E2E P90 | 判定 |
|-----|--------|----------|----------|---------|------|
| 0.5878（3-25，infra-opti）| 75.15% | 1.420s | 3.315s | 600.6s | ❌ 严重过载 |
| 0.43（本次）| 100% | 0.761s | 1.192s | 182.1s | ❌ E2E 临界超标 |
| **0.40（本次）** | **100%** | **0.680s** | **0.901s** | **107.2s** | **✅ ideal_rps** |
| 0.3415（Phase2）| 100% | 0.489s | 0.594s | 44.8s | ✅ |

---

### 📁 本次修改文件

| 文件 | 操作 |
|------|------|
| `results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-phase2-20260324/REPORT.md` | 新建 |
| `results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-phase2-20260324/*.png` | 新建（7张图） |
| `results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-phase2-20260324/*.html` | 新建 |
| `results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.400-20260327/REPORT.md` | 新建 |
| `results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.400-20260327/*.png` | 新建（7张图） |
| `results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.400-20260327/*.html` | 新建 |
| `results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.430-20260327/REPORT.md` | 新建 |
| `results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.430-20260327/*.png` | 新建（7张图） |
| `results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.430-20260327/*.html` | 新建 |
| `results/README.md` | 追加 2 条新实验索引 |

---

### ⏭️ 下次会话需关注（guoxue Eagle3）

1. **决定是否补测 0.41~0.42**：当前边界 `0.40 < ideal_rps < 0.43`，若需精确化可在此区间补探一点
2. **Phase 3 四点网格验证**：以 `IDEAL_RPS=0.40, PRODUCTION_RPS=0.23` 运行 Phase 3，脚本：`scripts/benchmark/run_phase3_grid_guoxue_eagle3_4h20.sh`
3. **生成最终 EVAL_REPORT.md**：Phase 3 完成后运行 `model-eval-report` Skill

---

## 🗓️ 会话日志 — 2026-03-27（下午/晚间）

### 主题：chart-deep-v5-2-235B 无限制环境重跑 Phase1+2 完成，报告分析 + 回放准备

---

### ✅ 实现了哪些功能

#### 1. Phase 2 新跑完成（无 max-running-requests 限制）

- Phase 2 三轮收敛：Round1(rps=1.4696 FAIL) → Round2(rps=1.4012 PASS) → Round3(rps=1.4350 PASS)
- **ideal_rps = 1.4350 req/s（86.1 RPM）**，bracket 宽 2.41%（< 3% 收敛阈值）
- 对比旧跑（受 128 限制）：ideal_rps 从 1.3360 → 1.4350，**提升 +7.4%**

| 档位 | RPS | TTFS P90 | E2E P90 | SLA |
|------|-----|---------|---------|-----|
| Round 1 | 1.4696 | 1838ms ❌ | 147.3s | FAIL |
| Round 2 | 1.4012 | 1438ms ✅ | 124.7s | PASS |
| Round 3（ideal） | **1.4350** | **1492ms ✅** | **130.6s** | **PASS** |

#### 2. Phase 3 启动（2026-03-27 22:46）

- `IDEAL_RPS=1.4350 PRODUCTION_RPS=0.5`，4档：0.5000 / 0.8117 / 1.1233 / 1.4350 req/s
- 每档 42min + 8.5min 冷却，预计约 3.2h（完成时间约 2026-03-28 02:06）
- 日志：`logs/chart-deep-v5-2/phase3_run_20260327_2246.log`

#### 3. Little's Law 计算（Phase 1 峰值档 con=311）

- Phase 1 con=311：decode_throughput=1597.5 tok/s，mean_E2E=180.9s
- **服务端承载并发 L = 1.5507 × 180.9 ≈ 280**

#### 4. Phase 2+3 合并目录（8档容量曲线）

- 合并新 Phase 2（3档无限制）+ 旧 Phase 2 低 RPS 有效档（5档，max_active < 128 未触发限制）
- 路径：`logs/chart-deep-v5-2/chart-deep-v5-2-8h20-phase23_merged_20260327/`

#### 5. 容量曲线图表生成

- YAML 配置：`configs/models/chart-deep-v5-2-235B/8h20_peak_finder_analysis.yaml`
- 输出：`results/chart-deep-v5-2-8h20-peak-finder-20260327/plot_latency_2d.html`（含8档SLA分析）
- SLA 拐点：rps=1.4696 时 TTFS P90 超标（1838ms > 1500ms），FAIL 点由 TTFS 先于 E2E 触发

#### 6. REPORT.md 生成（含完整 §0~§3 骨架）

- 路径：`results/chart-deep-v5-2-8h20-peak-finder-20260327/REPORT.md`
- 包含：三锚点表、Phase 1 各档吞吐、Phase 2 收敛过程、Phase 3 待填位（⏳ 占位）、上线建议

#### 7. 归档与配置更新

- `results/models/INDEX.yaml`：追加 chart-deep-v5-2-235B 条目（eval_status: in_progress）
- `configs/models/chart-deep-v5-2-235B/8h20.env`：
  - 更新 SERVER_URL → `172.21.65.249`
  - 新增 `REPLAY_DATASET_PATH` / `REPLAY_RPM` / `GROUP_NAME` 参数

#### 8. 回放测试方案就绪

- 数据集：`datas/output_chart-deep-v5/chart_deep_v5-2_235B_poisson_100_stitched.csv`（1755条，31min）
- 峰值 RPM=109，P90=91.6（超过单实例 ideal_rps=86.1 RPM，属压测场景）
- 执行命令（Phase 3 完成后触发）：
  ```bash
  nohup bash scripts/benchmark/run_replay.sh \
      configs/models/chart-deep-v5-2-235B/8h20.env \
      > logs/data-pipeline/chart-deep-v5-2-8h20_replay_$(date +%Y%m%d_%H%M%S).log 2>&1 &
  ```

---

### ❌ 遇到了哪些错误

1. **`multi_exp_compare` 使用相对路径时找不到实验文件**
   - 原因：工具从 `llm-benchmark` 目录运行，相对路径解析失败
   - 修复：YAML 中 `dir` 和 `output_dir` 改为绝对路径

---

### ✅ 如何解决错误

1. YAML 绝对路径修复：直接将 `/mnt/ai-infra/users/wnd/workspace/execute/guofan/...` 前缀写入 YAML 配置即可

---

### ⏭️ 下次会话需关注（chart-deep-v5-2）

1. **Phase 3 完成后**（约 2026-03-28 02:06）：
   - 追加 Phase 3 档位到合并目录：
     ```bash
     for d in logs/chart-deep-v5-2/chart-deep-v5-2-phase3_20260327_2246/qps*/; do
         [ -d "$d" ] && cp -rl "$d" "logs/chart-deep-v5-2/chart-deep-v5-2-8h20-phase23_merged_20260327/$(basename $d)"
     done
     ```
   - 重跑 `multi_exp_compare`（更新容量曲线图 + SLA 表）
   - 填写 REPORT.md §3 Phase 3 section
2. **回放测试**：Phase 3 完成后执行 `run_replay.sh`（~31min）
3. **生成最终 EVAL_REPORT.md**：Phase 3 + 回放完成后，用 `model-eval-report` Skill 生成完整报告
4. **确认业务峰值 RPM（Grafana）**：填入 REPORT.md 和 INDEX.yaml recommendation 字段
