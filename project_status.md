# 🗂️ 项目状态报告 Vol.2（2026-03-23 起）

---

## 📋 会话报告 — 2026-03-25（Cursor 历史会话批量导出）

### 📌 会话概览
- **时间**：2026-03-25
- **主要目标**：将项目开发过程中所有未导出的 Cursor 聊天会话（sessions 25-68）批量导出到 `clingo/sessions/` 目录，供 openclaw 角色内容深度优化使用
- **触发背景**：用户需要对 openclaw 的 Agent Heartbeat soul tool user 角色进行深化制定，需要完整的项目开发历史会话记录作为输入

---

### ✅ 实现功能

#### 1. 全量 Transcript 扫描与分析
- 扫描 `/home/ceceadmin/.cursor/projects/.../agent-transcripts/` 下 75 个 transcript 目录
- 通过内容匹配将已有的 sessions 01-24 中的明确 session 与对应 UUID 建立映射关系
- 识别用户手动导出的 sessions 36（`d8791542`，INDEX.yaml 更新）和 72（`849e07b1`，4×H20 QPS 分析）
- 通过 JSONL 文件 mtime 对所有未导出 transcript 排序，确定 sessions 25-35 和 37-68

#### 2. Sessions 25-35 批量导出（2026/3/13 — 2026/3/17）

| 编号 | 文件名 | 时间 | 主要内容 |
|------|--------|------|---------|
| 25 | `cursor_system_check_is_working` | 3/13 | 系统检查 |
| 26 | `cursor_llm_benchmark_inference_parameters` | 3/13 | LLM benchmark 推理参数说明 |
| 27 | `cursor_hepan_traffic_dataset_preparation` | 3/13 | hepan 流量数据集处理 |
| 28 | `cursor_mac_dmg_apple_security_warning` | 3/13 | Mac DMG 安全警告（个人） |
| 29 | `cursor_git_commit_milestone_progress` | 3/13 | 阶段性 git commit |
| 30 | `cursor_skills_docs_completeness_review` | 3/16 | Skill 文档完整性审查（172 条消息）|
| 31 | `cursor_git_status_document_adjustment` | 3/16 | 文档调整 git status |
| 32 | `cursor_session_batch_export_01_to_24` | 3/16 | **Sessions 01-24 批量导出执行过程** |
| 33 | `cursor_lingyu_model_index_update` | 3/17 | lingyu 模型 INDEX 更新 |
| 34 | `cursor_next_work_direction_planning` | 3/17 | **下一步工作方向整体规划（239 条消息，6073 行）** |
| 35 | `cursor_asset_management_dashboard_design` | 3/18 | Asset 管理 + Dashboard 设计 |

#### 3. Sessions 37-68 批量导出（2026/3/18 — 2026/3/24）

| 编号 | 文件名 | 时间 | 主要内容 |
|------|--------|------|---------|
| 37 | `cursor_chart_8tp_qps_evaluation` | 3/18 | chart-32b 8TP QPS 评估 |
| 38 | `cursor_chart_process_script_validation` | 3/18 | chart 数据处理脚本验证 |
| 39 | `cursor_chart_agent_model_migration_test` | 3/18 | **chart-agent 模型迁移测试（147 条消息）** |
| 40 | `cursor_ttfs_calculation_error_case_analysis` | 3/18 | TTFS 指标计算错误 Case 分析 |
| 41 | `cursor_chart_8tp_vs_4tp_comparison_report` | 3/19 | chart 8TP vs 4TP 对比分析报告 |
| 42 | `cursor_qps_peak_finder_skill_design` | 3/19 | **🔑 qps-peak-finder Skill 设计（234 条消息，4255 行）** |
| 43 | `cursor_index_yaml_update_continuation` | 3/19 | INDEX.yaml 更新续接 |
| 44 | `cursor_peak_finder_phase1_design_discussion` | 3/19 | 与同事讨论 Phase 1 先验知识应用 |
| 45 | `cursor_chart_agent_model_evaluation_progress` | 3/19 | chart-agent 模型评估推进（164 条消息）|
| 46 | `cursor_iphone_remote_mac_access` | 3/19 | iPhone 远程 Mac 操作（个人）|
| 47 | `cursor_ziwei_model_redeployment_test` | 3/19 | ziwei 模型重部署测试 |
| 48 | `cursor_benchmark_dataset_csv_cleanup` | 3/20 | benchmark CSV 清理 |
| 49 | `cursor_evaluation_experiments_overview` | 3/20 | 评估实验全景一览 |
| 50 | `cursor_tianji_querysafety_qps_peak_finder` | 3/20 | tianji-querysafety QPS Peak Finder |
| 51 | `cursor_guoxue_model_architecture_search` | 3/20 | guoxue 模型架构信息搜索 |
| 52 | `cursor_march20_daily_work_schedule` | 3/20 | **3/20 工作全景调度（190 条消息，3541 行）** |
| 53 | `cursor_guoxue_4h20_deployment_qps_test` | 3/23 | guoxue 4×H20 部署与 QPS 测试 |
| 54 | `cursor_guoxue_data_processing_pipeline` | 3/23 | **guoxue 数据处理 pipeline 深度分析（177 条消息，3485 行）** |
| 55 | `cursor_server_process_status_check` | 3/23 | 服务器进程状态检查 |
| 56 | `cursor_git_commit_march23_changes` | 3/23 | 3/23 变更 git commit |
| 57 | `cursor_chart_agent_data_structure_analysis` | 3/23 | chart-agent 数据结构分析 |
| 58 | `cursor_git_commit_chart_agent_progress` | 3/23 | **chart-agent 进展 git commit（83 条消息，13062 行）** |
| 59 | `cursor_guoxue_phase3_grid_progress_review` | 3/23 | guoxue Phase 3 网格进度回顾 |
| 60 | `cursor_git_commit_guoxue_eagle3_scripts` | 3/23 | **guoxue Eagle3 脚本 git commit（66 条消息，10427 行）** |
| 61 | `cursor_serve_py_results_visualization` | 3/23 | serve.py 结果可视化 |
| 62 | `cursor_chart_tokenizer_statistics` | 3/24 | chart 模型 Tokenizer 统计 |
| 63 | `cursor_model_traffic_tpm_statistics` | 3/24 | 模型流量 TPM 统计 |
| 64 | `cursor_intention_rag_dockerfile_analysis` | 3/24 | intention-rag Dockerfile 分析 |
| 65 | `cursor_eagle3_l20_qps_peak_finder_analysis` | 3/24 | **Eagle3 L20 QPS Peak Finder 分析（46 条消息）** |
| 66 | `cursor_guoxue_h20_phase3_directory_check` | 3/24 | guoxue H20 Phase 3 目录检查 |
| 67 | `cursor_chart_agent_data_conversion_prompt2` | 3/24 | chart-agent 数据转换 prompt2 |
| 68 | `cursor_march24_daily_work_report` | 3/24 | **3/24 工作日报（54 条消息）** |

#### 4. 格式清理与标准化
- 移除所有新导出文件中的系统注入标签：`<user_query>`、`</user_query>`、`<system_reminder>`、`<git_status>`、`<git_diff_from_branch_to_main>`、`<external_links>`、`<open_and_recently_viewed_files>`
- 格式与手动导出的 sessions（01-24、36、72）保持一致
- 标准化标题提取逻辑：从第一条用户消息中清理特殊标签后截取前 60 字符

---

### 🐛 遇到的问题与解决方案

#### 问题 1：Session 编号无法通过 mtime 精确还原
- **现象**：部分 sessions（如 22=881b9810 mtime 19:27）出现在 session 24（fdb354cd mtime 16:51）之后，与数字顺序矛盾
- **根因**：Cursor 的 session 编号基于对话**开始时间**，但 JSONL mtime 记录的是**最后一次修改时间**（用户可能在一个旧会话中继续追加消息）
- **解决**：接受编号近似，以"确保内容完整覆盖"为优先目标，不追求完美对齐 Cursor 内部序号

#### 问题 2：`<user_query>` 等系统标签污染输出内容
- **现象**：JSONL 中的用户消息包含 `<user_query>...</user_query>` 系统包装标签，被原样写入 markdown
- **解决**：导出完成后，用 Python regex 批量移除所有系统标签

#### 问题 3：Task subagent 工具集缺少 Read 工具
- **现象**：尝试用 Task 工具委托子 agent 执行时，报错 "Required tool READ not found"
- **解决**：改为直接在当前 Shell 中运行 Python 脚本完成批量导出

---

### 💡 关键技术决策

1. **分两批执行导出**：先 sessions 25-35（11 个），再 sessions 37-68（32 个），避免单次脚本过长出错
2. **mtime 排序作为近似编号依据**：虽然无法完美还原 Cursor 内部序号，但 mtime 顺序覆盖了完整的时间范围，适合 openclaw 优化的输入目的
3. **跳过个人/trivial 会话判断**：保留所有会话（包括 Mac DMG、iPhone 远程等个人咨询），因为这些也反映了真实的开发上下文

---

### 📊 本次会话成果

| 指标 | 数值 |
|------|------|
| 新导出 session 文件数 | 44 个（sessions 25-35 + 37-68）|
| `clingo/sessions/` 总文件数 | 69 个（含原有的 01-24、36、72）|
| 导出内容总行数 | ~91,000 行（约 3.6M 字符）|
| 最大单文件 | session 58（13,062 行，chart-agent git commit）|
| 最丰富内容 | session 42（4255 行，qps-peak-finder 完整设计过程）|

---

### ⚠️ 未完成事项

- Sessions 69-71 的 transcript 可能在当前列表中缺失（可能对应今日 March 25 的早期对话，或为 Cursor 内部计数的非用户可见会话），无需追补
- 本次 `clingo/sessions/` 内容覆盖范围：**2026/3/9 — 2026/3/24**，为 openclaw 优化提供完整的项目开发历程

---

### 📈 下次会话计划

1. 利用导出的会话内容对 openclaw 的 Agent Heartbeat soul tool user 角色进行深化制定
2. 继续 Eagle3 4×H20 的 QPS 评估（RPS ≤ 0.548 重跑探针）
3. chart-32b-agent benchmark 完成后执行 `scripts/migrate_chart_outputs.sh` 和 logs 目录迁移

---

> **说明**：本文件为 Vol.2，从 2026-03-23 起记录会话总结报告。历史完整记录见：
> - [`project_status_archive_vol1.md`](./project_status_archive_vol1.md)（截至 2026-03-23，3078 行）

---

## 📊 项目全景（承接 Vol.1 末尾快照）

### 项目背景

对 AI Infra 平台上线的 LLM 推理服务进行系统性容量评估。评估标准流程为 7 步（`model-evaluation-workflow` Skill）：

```
Step 0 信息收集 → Step 1 部署（本地/远端）→ Step 2 服务探测 → Step 3 数据处理
→ Step 4 远端连通性 → Step 5 QPS Peak Finder + 回放测试 → Step 6 结果分析 → Step 7 EVAL_REPORT
```

核心工具链：
- **QPS 评估**：`qps-peak-finder` Skill（三阶段：Phase 1 饱和探测 → Phase 2 自适应逼近 → Phase 3 生产网格）
- **数据处理**：`traffic-dataset-prep` Skill（DataConverter → DataSampler → DataInterpolator Poisson 插值）
- **结果分析**：`qps-peak-finder-analysis` Skill + `qps-sweep-comparison` Skill
- **交付报告**：`model-eval-report` Skill → `EVAL_REPORT.md`
- **在线监控**：`serve.py` Dashboard（端口 18999）+ VictoriaMetrics PromQL 接口

---

### 模型评估完整状态表（截至 2026-03-23）

| 模型 | 硬件 | ideal_rps | 业务峰值 | QPS 评估 | 回放测试 | EVAL_REPORT | 在线监控 | 整体状态 |
|------|------|-----------|---------|---------|---------|-------------|---------|---------|
| xinghan-hepan-72b-v1-2 | 8×L20 | — | — | ✅ | ✅ | ✅ | ❌ | 🟢 已交付 |
| xinghan-chart-32b-v1-1-agent | 8×L20 | 7.6132 req/s (457 RPM) | 118 RPM | ✅ | ✅ 99.19% | ✅ | ❌ | 🟢 已交付 |
| tianji-querysafety-4b-v2-3 | 4TP × 8实例 | 7.8554 RPS | 3584 RPM (÷8=448 RPM/实例) | ✅（Phase3缺2档）| ✅ 100% | ⚠️ 待补档 | ✅ | 🟡 基本完成 |
| xinghan-ziwei-32b-v1 | 8×L20 × 2实例 | 1.5902 req/s (95.4 RPM) | 52 RPM(7日峰) | ✅ | ✅ 历史 | ❌ 未生成 | ✅ v0.4.6 | 🟡 待 Step 7 |
| xinghan-guoxue-72b-v1-2-reason | 8×L20 (eagle3-test) | 0.2114 req/s (12.7 RPM) | 256 RPM | ✅ P1~P3+锚点 完成 | 🔄 结果待录入 | ✅ V2重写 | ✅ Dashboard | 🟡 待回放录入 |
| xinghan-guoxue-72b-v1-2-reason | 4×H20 (infra) | 0.5878 req/s (35.3 RPM) | 256 RPM | ✅ P1~P3 完成（锚点待跑）| 🔄 结果待录入 | ✅（含H20）| ✅ Dashboard | 🟡 待回放录入 |
| lingyu-235b-A22b-v9-2 | — | — | 758 RPM(7日峰) | ✅ | ❌ 无数据 | ❌ 未生成 | ✅ | 🟡 待 Step 7 |

---

### ⚠️ 关键风险（需关注）

| 优先级 | 风险 | 数据 | 建议行动 |
|--------|------|------|---------|
| 🔴 高 | **tianji 容量告急** | 7日峰值 3524 RPM，总容量 3840 RPM（**91.8%**）| 监控扩容时机，余量仅 8.2% |
| 🟠 中 | **guoxue L20 单实例容量严重不足** | ideal 12.7 RPM，峰值 256 RPM，需 ≥20 实例 8×L20 | Phase 3 分析完成后输出多实例部署建议 |
| 🟠 中 | **guoxue H20 单实例容量不足** | ideal 35.3 RPM，需 ≥8 实例 4×H20 | 同上，对比 L20 vs H20 综合建议 |
| 🟡 低 | **ziwei 过度配置** | 2 实例，7日峰值仅占 SLA 27% | 建议缩容至 1 实例，节省 8 卡 L20 |

---

### 基础设施状态

| 服务 | 状态 | 详情 |
|------|------|------|
| Dashboard（serve.py）| ✅ 运行中 | PID 4041588，端口 18999，日志 `logs/data-pipeline/serve_18999.log` |
| VictoriaMetrics | ✅ 可访问 | `http://172.21.52.62:8481`，支持新旧两种 SGLang 指标格式自动 fallback |

---

### 重要技术积累（Vol.1 沉淀的 Skill 更新）

| Skill | 主要更新内容 |
|-------|------------|
| `qps-peak-finder` | Phase 0 avg_output_len 权威分母原则；三阶段统一 DURATION/COOLDOWN 公式；EXIT trap 双保险机制；测试污染诊断表 |
| `qps-peak-finder-analysis` | STATUS_CANCELLED_BY_TIMELIMIT 过滤（避免成功率虚低）；success_rate 计算陷阱说明 |
| `traffic-dataset-prep` | 情况 C 路径（AI-data downloaded list 格式绕过 DataConverter）|
| `model-evaluation-workflow` | 情况 C 数据处理分支；DURATION/COOLDOWN 自动推算节 |

---

## 📈 下次会话计划（优先级排序）

### 优先级 1：guoxue V2 结果分析与报告生成

```bash
# 检查 Phase 3 完成状态
ls logs/guoxue-v2-phase3_20260322_1754/
ls logs/guoxue-v2-h20-phase3_20260322_1754/

# 运行 qps-peak-finder-analysis Skill（L20）
# Phase 1 目录: logs/guoxue-v2-eagle3-phase1_20260323_1804/
# Phase 2 目录: logs/guoxue-v2-phase2_20260320_1920/  (ideal_rps=0.2114)
# Phase 3 目录: logs/guoxue-v2-phase3_20260322_1754/

# 运行 qps-peak-finder-analysis Skill（H20）
# Phase 2 目录: logs/guoxue-v2-h20-phase2_20260320_2053/  (ideal_rps=0.5878)
# Phase 3 目录: logs/guoxue-v2-h20-phase3_20260322_1754/
```

### 优先级 2：生成 guoxue EVAL_REPORT.md

- 调用 `model-eval-report` Skill
- 重点：256 RPM 业务峰值下的多实例部署建议（L20 vs H20 对比）
- 参考：`results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md`

### 优先级 3：待补充 EVAL_REPORT 的模型

| 模型 | 所需输入 | 操作 |
|------|---------|------|
| xinghan-ziwei-32b-v1 | 已有 REPORT.md | 直接调用 model-eval-report Skill |
| lingyu-235b-A22b-v9-2 | 已有 REPORT.md | 直接调用 model-eval-report Skill |

### 优先级 4（可选）：tianji Phase 3 补档

- 缺 qps=7.5985 和 qps=7.7269 两档
- 补档后更新 REPORT.md 和 INDEX.yaml

---

## 以下为 Vol.2 新会话报告（2026-03-23 起）

---

## 会话报告 - 2026-03-23 下午场

### 📌 会话概览

- **日期**：2026-03-23
- **主要目标**：提取 xinghan-chart-32b-v1-1-agent 数据集中的 Agent 框架调用记录，交付给算法组
- **Git 分支**：main（ahead 1）
- **当前提交**：`8ae4a49`

---

### ✅ 成果

从 47,338 条原始下载数据中提取了 **40,315 条** Agent 框架调用记录（`星盘普通` 模型），生成交付文件：

```
datas/xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl
40,315 行 / 716MB
时间范围：2026-03-12 ~ 2026-03-16
```

**数据用途**：算法组将基于每条记录中 `role=a.prompt2` 字段（JSON 字符串，含出生信息、占星配置、用户提问）进行逻辑转化，重建裸模型输入。

---

### 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/data/extract_agent_calls.py` | 新增 | Agent 调用提取脚本（过滤 + 两阶段输出） |
| `datas/xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl` | 新增 | 最终交付文件（40,315 行，716MB） |

---

### 🐛 问题与解决方案

| 问题 | 原因 | 解决 |
|------|------|------|
| 提取数量 41,015 vs 文档估算 41,320，差 305 条 | 307 条 model/bot_id 均为空的日志残缺记录未被识别为 Agent 调用 | 全量分布统计确认，异常记录无 prompt2，正确排除 |
| 700 条 `prompt2` 为空 | 线上日志写入偶发丢失（logging bug），Agent 执行但参数未持久化 | 用户确认后二次过滤，仅保留有效 40,315 条 |

---

### 🎯 技术决策

1. **输出格式选完整 JSON Array**：用户明确选择保留 `role=b + role=ib + role=a` 三层结构，算法组可访问完整上下文（用户原始消息、星盘数据摘要、AI 回复）
2. **过滤掉 `prompt2` 为空的 700 条**：这些记录对算法组的输入改造任务无利用价值（缺少所有输入参数），过滤后交付更干净

---

### 📊 数据资产状态更新

| 文件 | 条数 | 用途 | 状态 |
|------|------|------|------|
| `xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl` | 47,338 | 原始全量数据 | 已存在（815MB） |
| `output_chart/xinghan-chart-32b-v1-1-agent_all.csv` | 6,016 | QPS benchmark（直接调用） | 已存在（已完成评估） |
| `xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl` | **40,315** | **算法组输入改造** | ✅ 本次新增（716MB） |

---

### ⚠️ 未完成事项

本次会话任务已全部完成，无遗留项。主线任务（guoxue V2 分析报告）的优先级不变，见上方「下次会话计划」。

---

### 📈 下次会话计划（继承自上次）

1. **运行 qps-peak-finder-analysis Skill** → 生成 guoxue L20（8×L20 eagle3）+ H20（4×H20）各自的 `REPORT.md`
2. **合并 L20 vs H20 结果** → 写入 `model-context.md`，输出多实例部署建议
3. **生成 guoxue EVAL_REPORT.md**（model-eval-report Skill）→ 256 RPM 峰值下实例数建议
4. **ziwei / lingyu EVAL_REPORT.md**（Step 7，优先级次之）

---


---

## 会话报告 - 2026-03-23 晚场

### 📌 会话概览

- **日期**：2026-03-23（下午至傍晚）
- **主要目标**：guoxue 评估资产清理——V1 兜底数据实验归档、EVAL_REPORT V2 重写、生产锚点补测
- **Git 分支**：main（ahead 1，未提交本次变更）
- **当前提交**：`8ae4a49` docs(progress): 记录 2026-03-20 下午场会话

---

### ✅ 成果

#### 资产清理
- **V1 实验归档**：4 个目录移至 `results/archive/guoxue-v1-deprecated/`，附 `ARCHIVED.md` 说明废弃原因（数据 system prompt 错误，业务峰值口径 43 vs 256 RPM）
- **INDEX.yaml 修正**：主配置还原为 L20，`sla_max_qps_rps` 从 0.5878 修正为 0.2114，recommendation 文本按用户要求精确更新
- **Dashboard 自动生效**：serve.py 无需重启，INDEX 变更立即反映在 http://172.21.208.11:18999/

#### EVAL_REPORT.md 完全重写（V2）

核心结论修正：

| 维度 | V1（废弃）| V2（当前正确）|
|------|----------|-------------|
| 业务峰值 | 43 RPM（stream only）| 256 RPM（stream 43 + MCP 213）|
| 推荐部署 | 4实例×8L20=32卡 | **≥20实例×8L20（推荐20实例=160卡，余量3%）** |
| H20 定位 | — | **临时过渡**（6实例，L20不足期间）|
| 单实例上限 | 14.96 RPM | **12.7 RPM** |

新增内容：§5「L20 在线流量说明」（MCP+stream 两通道口径解析），L20 陡崖型拐点运维警示。

#### 生产锚点补测结果（L20 @ 0.195 req/s）

| 指标 | 值 | SLA |
|------|------|-----|
| 实际发送 | 703 条 | — |
| 成功率 | **100.0%** | ✅（≥99%）|
| TTFS P90 | **730 ms** | ✅（<1500ms）|
| E2E P90 | **152.2 s** | ✅（<180s，余量 15.4%）|

结论：生产工作点（0.195 req/s）处于稳态区，距 ideal_rps 仅 8.5%，SLA 完全合规。

---

### 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/archive/guoxue-v1-deprecated/ARCHIVED.md` | 新增 | V1 实验废弃说明 |
| `results/archive/guoxue-v1-deprecated/{4个旧目录}` | 移动 | 从 results/ 迁入 archive |
| `results/README.md` | 修改 | 旧条目标注归档，新增 V2 三节详细说明 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | 修改 | V2 数据集路径，回放状态更新 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md` | **重写** | V2 版，L20 主方案，H20 临时，新增流量说明节 |
| `results/models/INDEX.yaml` | 修改 | deployment 改 L20，sla_max_qps_rps=0.2114，recommendation 更新 |
| `results/guoxue-v2-8tp-peak-finder-20260323/REPORT.md` | 修改 | Phase 3 新增 0.1950 行，0.05 行改标"最低验证档" |
| `scripts/benchmark/run_prod_anchor_guoxue8tp.sh` | 新增 | L20 生产锚点单档测试脚本 |
| `logs/guoxue-v2-8tp-prod-anchor_20260323_155707/` | 新增 | 补测日志及结果 CSV |
| `progress.md` | 追加 | 本次会话工作日志 |

---

### 🐛 问题与解决方案

| 问题 | 解决 |
|------|------|
| StrReplace 对含全角标点行匹配失败 | 改用 Python `content.replace()` |
| EVAL_REPORT 错将 H20 列为推荐方案 | 用户纠正后重写：L20 主，H20 临时 |
| INDEX.yaml 展示拐点 0.5878（H20 值）| 修正 `sla_max_qps_rps` 为 0.2114 |
| 补测成功率显示 83.4%（实际 100%）| status=-5 为 buffer 未发送，重以实发数为分母 |

---

### 🎯 技术决策

1. **归档方式选物理移动而非原地标注**：用户选择干净隔离，`results/` 主目录只保留 V2 有效实验
2. **H20 定位为临时过渡**：H20 性能更优（2.78×），但业务长期以 L20 为主，H20 仅在 L20 资源不足期间补位，EVAL_REPORT 叙述需准确反映此定位
3. **生产锚点补单档而非重跑 Phase 3**：已有数据覆盖生产点两侧，补跑一档在 1h 内完成，成本最低

---

### ⚠️ 未完成事项（本次会话遗留）

| 项 | 状态 | 操作 |
|----|------|------|
| guoxue 回放测试（H20 混合）结果录入 | 测试已完成（14:56 启动），**结果尚未读取并写入 EVAL_REPORT.md §3 和 INDEX.yaml** | 下次会话优先处理 |
| H20 生产锚点补测（0.195 req/s）| 待用户调整 endpoint URL | 用户告知 URL 后立即执行 `run_prod_anchor_guoxue4h20.sh` |
| H20 REPORT.md Phase 3 更新 | 待 H20 锚点完成 | 同 L20 处理方式，增行 + 重标 0.05 档 |

---

### 📈 模型评估完整状态表（更新至 2026-03-23 晚）

| 模型 | 硬件 | ideal_rps | 业务峰值 | QPS 评估 | 回放测试 | EVAL_REPORT | 整体状态 |
|------|------|-----------|---------|---------|---------|-------------|---------|
| xinghan-hepan-72b-v1-2 | 8×L20 | — | — | ✅ | ✅ | ✅ | 🟢 已交付 |
| xinghan-chart-32b-v1-1-agent | 8×L20 | 7.61 req/s | 118 RPM | ✅ | ✅ 99.19% | ✅ | 🟢 已交付 |
| tianji-querysafety-4b-v2-3 | 4TP×8实例 | 7.86 RPS | 3584 RPM | ✅（Phase3缺2档）| ✅ 100% | ⚠️ 待补档 | 🟡 基本完成 |
| xinghan-ziwei-32b-v1 | 8×L20×2实例 | 1.59 req/s | 52 RPM | ✅ | ✅ | ❌ 待 Step 7 | 🟡 待报告 |
| **xinghan-guoxue-72b-v1-2-reason** | **8×L20（目标）** | **0.2114 req/s** | **256 RPM** | **✅+锚点补测✅** | **🔄 结果待录入** | **✅ V2重写** | **🟡 待回放录入** |
| **xinghan-guoxue-72b-v1-2-reason** | **4×H20（临时）** | **0.5878 req/s** | **256 RPM** | **✅（锚点待跑）** | **🔄 结果待录入** | **✅（含H20节）** | **🟡 待回放录入+锚点** |
| lingyu-235b-A22b-v9-2 | — | — | 758 RPM | ✅ | ❌ | ❌ 待 Step 7 | 🟡 待报告 |

---

### 📈 下次会话计划（优先级排序）

1. **🔴 必做：guoxue 回放测试结果录入**
   - 读取 `logs/guoxue-72b-mixed-10inst_replay_20260323_145604/` CSV 结果
   - 补充 EVAL_REPORT.md §3 回放结论
   - 更新 INDEX.yaml `replay_*` 字段和 model-context.md

2. **🟠 待用户配合：H20 生产锚点补测**
   - 用户调整 H20 endpoint URL → 执行补测脚本
   - 更新 `guoxue-v2-h20-peak-finder-20260323/REPORT.md` Phase 3 表格

3. **🟡 可选：ziwei / lingyu EVAL_REPORT.md**（Step 7）

4. **🟡 可选：tianji Phase 3 缺失 2 档补跑**

---

## 会话报告 - 2026-03-23 深夜场

### 📌 会话概览

- **日期**：2026-03-23（深夜）
- **主要目标**：
  1. 修正 EVAL_REPORT.md 中混合部署描述（6×H20 + 4×L20）
  2. 补充三锚点对照与 Phase 1 饱和探测摘要
  3. INDEX.yaml guoxue 条目双配置重构（方案 A）
  4. chart-32b 状态标记为重新评估中
- **Git 分支**：main（ahead 1）
- **参考上次会话**：[guoxue Phase3 分析 + 回放测试](70814b28-5d87-4d73-a2f6-e351429941da)

---

### ✅ 成果

#### EVAL_REPORT.md（`results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md`）

**6 处混合部署纠正**（改动前均为"6×H20 临时"，改动后全部反映"6×H20 + 4×L20 混合 10 实例，262.6 RPM，余量 2.6%"）：
- 摘要表"当前临时方案"行
- §1 部署配置"临时配置"行
- §3 残留的旧"测试中"表格（删除）
- §5 流量说明注脚
- §6 当前方案表格（单列 → 三列对比）
- §6 运维建议第 5 条

**§4 扩充（新增两小节）**：
- 新增 §4.2 三锚点对照（极限 RPS / 理想 RPS / 服务端并发，L20 vs H20 横向比较）
- 新增 §4.4 Phase 1 饱和探测摘要（各档吞吐数据，来自两个 REPORT.md）
- 原 §4.2/4.3 顺移为 §4.3/4.5

#### INDEX.yaml（`results/models/INDEX.yaml`）

**guoxue 条目双配置重构（方案 A：主从后缀）**：
- 主配置（无后缀）= 8×L20：`saturation_rps` 从 0.7348 → **0.2498**，全套相关字段更新
- 新增 `_h20` 后缀字段：`sla_max_qps_rps_h20=0.5878`、`saturation_rps_h20=0.7348` 等 8 个字段
- 新增效率比较：`h20_vs_l20_qps_ratio: 2.78`、`h20_vs_l20_per_card_ratio: 5.56`
- `current_interim` → `current_mixed`，deployment 描述更新

**chart-32b 条目状态更新**：
- `eval_status: completed` → `re_evaluating`
- `eval_completed_date` → `null`
- 新增 `reeval_reason`、`reeval_status` 字段记录重测进度
- `recommendation` 改为 ⚠️ 结论挂起

---

### 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md` | 修改 | 6 处混合部署纠正 + §4 新增两小节（190→225 行）|
| `results/models/INDEX.yaml` | 修改 | guoxue 双配置重构（主从后缀）+ chart-32b 重评状态 |
| `progress.md` | 追加 | 本次深夜场工作日志 |

---

### 🐛 问题与解决方案

| 问题 | 解决 |
|------|------|
| StrReplace 对含全角字符的行多次匹配失败 | Python `open/replace/write` + `repr()` 逐行确认精确内容 |
| INDEX.yaml 主配置标 L20 但极限 QPS 字段实为 H20 数据 | brainstorming 三方案讨论，选方案 A（主从后缀），整块 Python 替换 |

---

### 🎯 技术决策

1. **方案 A（主从后缀）优于方案 B（嵌套块）**：与现有 `chart-32b` 的 `_4tp` 命名惯例一致，无需改 schema，机器可读，两套配置数据对等保留
2. **`saturation_*` 主配置以目标硬件（L20）为准**：INDEX.yaml 的 `saturation_rps` 字段语义为"目标部署的极限 RPS"，H20 作为过渡配置用 `_h20` 后缀标注，逻辑更清晰
3. **chart-32b 用 `re_evaluating` 而非 `invalid`**：测试基础设施和流程无问题，数据源存疑，等待新数据后可直接续接，状态不宜太悲观

---

### ⚠️ 未完成事项

| 项 | 状态 | 下步操作 |
|----|------|---------|
| chart-32b V2 重测 | 等待算法新数据（预计 2026-03-25）| 收到数据后走 Step 3（数据处理）→ Step 5（QPS Peak Finder）|
| guoxue H20 生产锚点补测（0.195 req/s）| 待用户调整 endpoint URL | 告知 URL 后执行 `run_prod_anchor_guoxue4h20.sh` |

---

### 📊 模型评估完整状态表（更新至 2026-03-23 深夜）

| 模型 | 硬件 | ideal_rps | 业务峰值 | QPS 评估 | 回放测试 | EVAL_REPORT | 整体状态 |
|------|------|-----------|---------|---------|---------|-------------|---------|
| xinghan-hepan-72b-v1-2 | 8×L20 | — | — | ✅ | ✅ | ✅ | 🟢 已交付 |
| **xinghan-chart-32b-v1-1-agent** | 8×L20 | 7.61 req/s | 118 RPM | ⚠️ V1存疑 | ⚠️ V1存疑 | ⚠️ 挂起 | 🔴 **重新评估中** |
| tianji-querysafety-4b-v2-3 | 4TP×8实例 | 7.86 RPS | 3584 RPM | ✅（Phase3缺2档）| ✅ 100% | ⚠️ 待补档 | 🟡 基本完成 |
| xinghan-ziwei-32b-v1 | 8×L20×2实例 | 1.59 req/s | 52 RPM | ✅ | ✅ | ❌ 待 Step 7 | 🟡 待报告 |
| **xinghan-guoxue-72b-v1-2-reason** | **6×H20 + 4×L20 混合** | L20:0.2114 / H20:0.5878 | **256 RPM** | **✅ 全部完成** | **✅ 99.89%** | **✅ V2（含混合部署）** | 🟡 H20锚点待补 |
| lingyu-235b-A22b-v9-2 | — | — | 758 RPM | ✅ | ❌ | ❌ 待 Step 7 | 🟡 待报告 |

---

### 📈 下次会话计划（优先级排序）

1. **🟠 待用户配合：H20 生产锚点补测（0.195 req/s）**
   - 用户调整 endpoint URL → 执行 `run_prod_anchor_guoxue4h20.sh`
   - 更新 `guoxue-v2-h20-peak-finder-20260323/REPORT.md` Phase 3 表格

2. **🟡 chart-32b V2 重测准备**（预计 2026-03-25 收到新数据）
   - 收到算法新数据 → Step 3 数据处理 → Step 5 QPS Peak Finder（8TP 为主）

3. **🟡 ziwei / lingyu EVAL_REPORT.md**（Step 7，直接可做）

4. **🟡 tianji Phase 3 补跑缺失 2 档**


---

# 会话报告 — 2026-03-23（夜场）：guoxue 4H20+9L20 回放分析 & EVAL_REPORT 更新

## 📌 会话概览

- **日期**：2026-03-23（周一）夜场
- **主要目标**：对 4×4H20+9×8L20 新部署方案完成回放测试结果分析，撰写比对报告，并更新 EVAL_REPORT.md 反映当前部署实况
- **Git 分支**：main（ahead 1）
- **涉及模型**：xinghan-guoxue-72b-v1-2-reason

---

## ✅ 成果

### 1. 4H20+9L20 回放测试结果（256 RPM，✅ SLA 全通过）

| 指标 | 实测值 | SLA | 余量 |
|------|--------|-----|------|
| 成功率 | 99.89% | >=99% | ✅ |
| TTFT P90 | 1.029s | <=1.5s | 31% |
| TTFS P90 | 1.182s | <=1.5s | 21% |
| E2E P90 | 115.5s | <=180s | 36% |
| E2E P99 | 148.8s | — | ✅（SLA 83%，需关注）|

与基线方案（6H20+4L20）相比延迟小幅升高（E2E P90 +14.7%），成功率完全一致，新方案可投入生产。

### 2. 新增报告与归档文件

| 文件 | 操作 | 说明 |
|------|------|------|
| results/guoxue-v2-4h20-9l20-replay-20260323/REPORT.md | 新建 | 完整报告，含双方案横向对比 |
| results/guoxue-v2-4h20-9l20-replay-20260323/*.html+png×7 | 分析产出 | offline_analysis.py 产出 |
| results/README.md | 修改 | 目录表 + 详细节新增条目 |
| results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md | 修改 | 追加 replay2_* 字段 |
| results/models/INDEX.yaml | 修改 | replay2_* + linked_experiments 新条目 |
| results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md | 修改 | 5 处增量更新 |

### 3. EVAL_REPORT.md 关键变更

| 位置 | 变更摘要 |
|------|---------|
| 摘要-上线建议 | 改为两轮回放均通过 |
| 摘要-当前部署 | 6H20+4L20 → 4H20+9L20（三月余量 +31%）|
| 摘要-风险提示 | E2E P99=148.8s（SLA 83%）需关注 |
| 第 3 节 | 单表格 → 方案一/方案二双表格对比 |
| 第 6 节 | 实例数、GPU 总数、总承载上限、运维建议同步更新 |
| 实验索引 | 新增两行回放实验（基线 + 新方案）|

---

## 🔧 文件变更汇总

| 文件 | 操作 | 核心变更 |
|------|------|---------|
| results/guoxue-v2-4h20-9l20-replay-20260323/REPORT.md | 新建 | 221 行，完整回放报告 |
| results/guoxue-v2-4h20-9l20-replay-20260323/分析产出 | 新建 | HTML + 7张PNG |
| results/README.md | 修改 | +31 行 |
| results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md | 修改 | +10 行 replay2_* |
| results/models/INDEX.yaml | 修改 | +11 行 replay2_* + linked |
| results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md | 修改 | 5 处增量（约 +50 行）|

---

## 🐛 问题与解决方案

| # | 问题 | 根因 | 解决 |
|---|------|------|------|
| 1 | offline_analysis.py 用 usecols 读 CSV 报错 | 回放 CSV 不含 ttft_s 等计算列 | 完整运行脚本，从 log 提取分位数 |
| 2 | EVAL_REPORT.md StrReplace 含特殊字符失败 | 全角标点 + emoji 干扰匹配 | Python readlines() 按行号精确替换 |

---

## 🎯 技术决策

1. **model-eval-report Skill 增量模式**：EVAL_REPORT 已有结构，只补充新数据，不全量重跑
2. **双方案并列展示**：§3 以方案一/方案二并列表格，便于交付时说明迁移前后性能变化
3. **风险提示前置**：E2E P99=148.8s 达 SLA 83%，提升到摘要层，非仅在详情中说明

---

## ⚠️ 未完成事项

1. **H20 生产锚点补测**（遗留）：用户需调整 endpoint URL → 执行 run_prod_anchor_guoxue4h20.sh
2. **guoxue eagle3 端点测试状态**：用户已打开 logs/guoxue-v2-eagle3-phase2_20260323_1923/phase2_checkpoint.md，说明有并行 eagle3 评测任务，本次会话未处理

---

## 📈 下次会话计划（优先级）

1. **🟠 H20 生产锚点补测** — 用户调整 endpoint 后立即执行
2. **🟡 guoxue eagle3 测试状态确认** — 查看 phase2_checkpoint.md 确认当前轮次结论
3. **🟡 ziwei / lingyu EVAL_REPORT.md**（Step 7，直接可做）
4. **🟡 chart-32b V2 重测**（待算法新数据，预计 2026-03-25）

---

### 📊 模型评估完整状态表（更新至 2026-03-23 夜场）

| 模型 | 硬件 | ideal_rps | 业务峰值 | QPS 评估 | 回放测试 | EVAL_REPORT | 整体状态 |
|------|------|-----------|---------|---------|---------|-------------|---------|
| xinghan-hepan-72b-v1-2 | 8×L20 | — | — | ✅ | ✅ | ✅ | 🟢 已交付 |
| xinghan-chart-32b-v1-1-agent | 8×L20 | 7.61 req/s | 118 RPM | V1存疑 | V1存疑 | 挂起 | 🔴 重新评估中 |
| tianji-querysafety-4b-v2-3 | 4TP×8实例 | 7.86 RPS | 3584 RPM | ✅（Phase3缺2档）| ✅ 100% | 待补档 | 🟡 基本完成 |
| xinghan-ziwei-32b-v1 | 8×L20×2实例 | 1.59 req/s | 52 RPM | ✅ | ✅ | ❌ 待 Step 7 | 🟡 待报告 |
| **xinghan-guoxue-72b-v1-2-reason** | **4×H20 + 9×L20** | L20:0.2114 / H20:0.5878 | **256 RPM** | **✅ 全部完成** | **✅ 两轮均 99.89%** | **✅ V2（双回放方案）** | 🟡 H20锚点待补 |
| lingyu-235b-A22b-v9-2 | — | — | 758 RPM | ✅ | ❌ | ❌ 待 Step 7 | 🟡 待报告 |

---

---

# 📊 会话报告 — 2026-03-24

## 📌 会话概览

- **日期**：2026-03-24
- **主要目标**：对昨日执行的 Eagle3 8×L20 QPS 三阶段压测进行完整结果分析、归档与报告生成
- **Git 分支**：main（ahead 1）
- **涉及模型**：xinghan-guoxue-72b-v1-2-reason（Eagle3 8×L20 推测解码加速评估）

---

## ✅ 成果

### 1. Eagle3 8×L20 QPS Peak Finder 分析完成（Step 6）

三阶段压测（昨日执行，今日分析）关键结论：

| 操作点 | RPS | RPM | TTFS P90 | E2E P90 | 成功率 |
|--------|-----|-----|---------|---------|--------|
| 极限 RPS（Phase 2 首档 FAIL）| 0.3486 | 20.9 | 1.416s | 289.4s | 100% |
| **理想 RPS（Phase 2 收敛）** | **0.3169** | **19.0** | **769ms ✅** | **172.1s ✅** | **99.9% ✅** |
| 生产 RPM 锚点（Phase 3 最低档）| 0.1950 | 11.7 | 754ms ✅ | 96.2s ✅ | 99.9% ✅ |
| Little's Law 服务端并发 | 0.2641×142.9s | — | — | — | **≈ 37** |

**Eagle3 vs Vanilla 8×L20 对比**：

| 指标 | Vanilla | Eagle3 | 提升 |
|------|---------|--------|------|
| ideal_rps | 0.2114 req/s | **0.3169 req/s** | **+50%（1.50×）** |
| 极限 RPS | 0.2498 req/s | 0.3486 req/s | +40% |
| peak decode_throughput | 359.7 t/s | 573.5 t/s | +59% |
| TTFS P90（ideal档）| 727ms | 769ms | +6%（可忽略）|
| E2E P90（ideal档）| 153.5s | 172.1s | +12%（仍 SLA 合规）|

### 2. 完整 REPORT.md 生成与完善

- 初版生成后对照 vanilla REPORT 格式补全所有缺失内容
- 新增 Phase 3 P50/P99 实测数据（Python 解析 token_list 提取）
- 新增 Eagle3 vs Vanilla 完整对比表
- 新增拐点分析详细文字说明、上线建议保守/激进区分和告警阈值

### 3. 实验目录 Step 6.5 归档（model-evaluation-workflow 规范）

| 文件 | 操作 |
|------|------|
| `logs/guoxue-v2-eagle3-phase1_20260323_1804/README.md` | ✅ 新建 |
| `logs/guoxue-v2-eagle3-phase2_20260323_2054/README.md` | ✅ 新建（有效收敛运行）|
| `logs/guoxue-v2-eagle3-phase3_20260324_0153/README.md` | ✅ 新建 |
| `results/README.md` | ✅ 新增 eagle3 条目 |
| `results/models/.../model-context.md` | ✅ 追加 `eagle3_8l20_*` 字段 |
| `results/models/INDEX.yaml` | ✅ linked_experiments 追加 eagle3 路径 |

### 4. 日志清理（释放磁盘 ~485 MB）

| 清理对象 | 原因 |
|---------|------|
| `logs/guoxue-v2-eagle3-phase2_20260323_1923/`（485 MB）| Phase 2 首次运行测试污染，TTFS P90=124.7s |
| `guoxue_eagle3_phase2_20260323_192312.log`（63 KB）| 对应污染运行 log |
| `guoxue_eagle3_phase2_20260323_184311.log`（8.4 KB）| 18:43 abort 尝试，无数据目录 |

---

## 🔧 文件变更汇总

| 文件 | 操作 | 说明 |
|------|------|------|
| `configs/models/.../eagle3_8l20_peak_finder_analysis.yaml` | ✅ 新建 | 图表生成配置 |
| `logs/guoxue-v2-eagle3-phase23_merged_20260323/`（硬链接）| ✅ 新建 | Phase 2+3 合并目录（8档），不额外占磁盘 |
| `results/guoxue-v2-eagle3-8l20-peak-finder-20260323/` | ✅ 新建 | REPORT.md + 3张 HTML 图表 |
| `results/guoxue-v2-eagle3-8l20-peak-finder-20260323/REPORT.md` | ✅ 完善 | 补 P50/P99、对比表、拐点分析、上线建议 |
| `logs/*/README.md` × 4 | ✅ 新建 | Phase1 / Phase2(污染标注) / Phase2(收敛) / Phase3 |
| `results/README.md` | ✅ 修改 | 新增目录总览行 + 详细说明段 |
| `results/models/.../model-context.md` | ✅ 修改 | 追加 eagle3_8l20_* 字段段落（约 +25 行）|
| `results/models/INDEX.yaml` | ✅ 修改 | linked_experiments +1 行 |
| `progress.md` | ✅ 修改 | 本次完整会话日志 |

---

## 🐛 问题与解决方案

| # | 问题 | 根因 | 解决 |
|---|------|------|------|
| 1 | Phase 2 首次运行数据全 FAIL（TTFS P90=124s）| Phase 1 未充分冷却，残留在途请求污染 | 作废第一次数据，冷却后第二次重跑正常 |
| 2 | token_list 计算 decode_tp（220 t/s）与 metrics_cache（573 t/s）不一致 | 脚本用 `old_response_len` 作分子，非实际 token 数；但 max_rps_estimate 两种算法结果相同（0.2641）| 统一用 checkpoint 值，理解计算口径差异 |
| 3 | phase23_merged `du` 显示 3.6G 看似翻倍 | `cp -rl` 硬链接，`du` 重复计数 | `ls -li` 验证 inode 相同，确认不额外占磁盘 |

---

## 🎯 技术决策

1. **测试污染识别方法**：同档位 TTFS P90 从 124.7s→0.746s，跨越 2 个数量级，是测试污染的确定性信号，不需要其他辅助证据
2. **Phase 3 P99 安全建议**：ideal_rps 档 E2E P99=207.7s 超过 180s SLA，在 REPORT 中明确注明，给出 P99 友好的保守上限 0.2763 req/s（16.6 RPM）
3. **Eagle3 vs Vanilla 对比**：avg_output_len 差异（2172 vs 1386）导致 E2E 绝对值上升，但 RPS 提升 50% 是实质性收益；在报告中明确区分"token 数增加"与"性能退化"

---

## ⚠️ 未完成事项

1. **EVAL_REPORT.md 未更新 Eagle3 章节** — guoxue 的 EVAL_REPORT 尚未包含 Eagle3 评估结论，待用户确认是否需要
2. **4×H20 Eagle3 Phase 2 进行中** — `logs/guoxue-v2-eagle3-4h20-phase2_20260324_0422/` 于今日凌晨启动，结果未知，待完成后分析
3. **H20 生产锚点补测**（持续遗留）— 需用户确认 endpoint URL

---

## 📈 下次会话计划（优先级）

1. **🟠 Eagle3 4×H20 Phase 2 完成状态确认** — 查看 `guoxue-v2-eagle3-4h20-phase2_20260324_0422/` 收敛结果，若完成则执行 Phase 3 + 分析归档
2. **🟠 H20 生产锚点补测** — 持续遗留，用户确认 endpoint 后执行
3. **🟡 guoxue EVAL_REPORT.md 追加 Eagle3 章节** — 在 §5 或附录补充 Eagle3 vs vanilla 对比结论
4. **🟡 ziwei / lingyu EVAL_REPORT.md**（Step 7，直接可做）
5. **🟡 chart-32b V2 重测**（待算法新数据）

---

## 📊 模型评估完整状态表（更新至 2026-03-24）

| 模型 | 硬件 | ideal_rps | 业务峰值 | QPS 评估 | 回放测试 | EVAL_REPORT | 整体状态 |
|------|------|-----------|---------|---------|---------|-------------|---------|
| xinghan-hepan-72b-v1-2 | 8×L20 | — | — | ✅ | ✅ | ✅ | 🟢 已交付 |
| xinghan-chart-32b-v1-1-agent | 8×L20 | 7.61 req/s | 118 RPM | V1存疑 | V1存疑 | 挂起 | 🔴 重新评估中 |
| tianji-querysafety-4b-v2-3 | 4TP×8实例 | 7.86 RPS | 3584 RPM | ✅（Phase3缺2档）| ✅ 100% | 待补档 | 🟡 基本完成 |
| xinghan-ziwei-32b-v1 | 8×L20×2实例 | 1.59 req/s | 52 RPM | ✅ | ✅ | ❌ 待 Step 7 | 🟡 待报告 |
| **xinghan-guoxue-72b-v1-2-reason（vanilla）** | 8×L20 / 4×H20 | L20:0.2114 / H20:0.5878 | 256 RPM | ✅ | ✅ 两轮 99.89% | ✅ V2 | 🟡 H20锚点待补 |
| **xinghan-guoxue-72b-v1-2-reason（Eagle3）** | **8×L20** | **0.3169 req/s（19 RPM）** | **256 RPM** | **✅ 三阶段全完成** | — | ❌ 待追加 | 🟡 报告已完成，EVAL待更新 |
| xinghan-guoxue-72b-v1-2-reason（Eagle3 4×H20）| 4×H20 | 进行中 | 256 RPM | 🔄 Phase 2 进行中 | — | — | 🔄 评估中 |
| lingyu-235b-A22b-v9-2 | — | — | 758 RPM | ✅ | ❌ | ❌ 待 Step 7 | 🟡 待报告 |

---

---

# 会话报告 - 2026-03-24 下午场

## 📌 会话概览

- **日期**: 2026-03-24
- **主要目标**: guoxue 4×H20 Phase 3 数据有效性核查 + logs 日志归档清理
- **Git 分支**: main
- **当前提交**: 8ae4a49

## ✅ 成果

### 1. guoxue 4×H20 Phase 3 数据质量核查与确认

- **识别污染**：3/22 两次并发 Phase 3 run（1754 + 1759）在同一 endpoint 上同时运行，导致服务队列饱和
  - timeout 率：qps_0.5878 档位 **1819~1822 个**（3/23 独立 run 为 0）
  - TTFS P90：**273~274s**（正常应 <1s）
  - 成功率：**11.6~11.7%**（正常 83.3%）
- **确认有效**：`guoxue-v2-h20-phase3_20260323_1024` 是干净的独立重测
  - 全档 timeout = 0，cancel 率精确 16.7%，E2E P90 单调递增
  - 已被 `phase23_merged_20260323` 采纳（argv hardlink 指向 1024）
  - `qps_0.0500` 低负载档位从 3/22 复用可信（三次运行指标完全一致）

### 2. logs 日志归档清理

- 新建 `logs/archive/data-pipeline/` 目录
- 将 58 个 data-pipeline log 中 **37 个**孤立/过期文件移入归档，保留 **21 个**活跃文件
- `logs/*.log`（7个）全部保留（对应目录均存在）
- 归档过程使用了人工精确核定（自动模糊匹配误判较多）

## 🔧 文件变更

| 文件/目录 | 操作 | 说明 |
|---|---|---|
| `logs/archive/data-pipeline/`（新建） | 创建 | 存放 37 个孤立 data-pipeline 日志 |
| `logs/data-pipeline/*.log`（37个） | 移动至 archive | 对应目录已删除或已归档 |
| `progress.md` | 追加 | 本次会话工作日志 |
| `project_status.md` | 追加 | 本次会话状态报告 |

## 🐛 问题与解决方案

| 问题 | 根因 | 解决 |
|---|---|---|
| 3/22 两次 Phase 3 并发干扰 | 两个进程同时对同一 endpoint 发压 | 以 3/23 独立重测数据为准，1754/1759 目录已删除 |
| 自动模糊匹配误判（如 142856 匹配到 145239） | 时间戳不完全一致，关键词匹配过宽松 | 人工逐一核定 58 个文件，精确分组，零遗漏 |

## 🎯 技术决策

1. **Phase 3 1759 数据废弃**：统计指标（TTFS P90 升高 500x，timeout 从 0 到 1800+）已明确证明并发干扰，无需保留
2. **qps_0.0500 复用可信**：三次运行指标完全一致（TTFS P90=578~580ms，E2E P90=81.6~81.7s），低负载下并发影响可忽略
3. **归档目录独立设置**：`archive/data-pipeline/` 而非平铺入 `archive/`，保持 data-pipeline 日志与 benchmark 结果目录的命名空间分离

## ⚠️ 未完成事项

1. Eagle3 4×H20 Phase 2 尚在进行中
2. guoxue EVAL_REPORT.md Eagle3 章节未追加
3. ziwei / lingyu Step 7 EVAL_REPORT 未执行

## 📈 下次会话计划

1. **🟠 确认 Eagle3 4×H20 Phase 2 收敛结果** → 执行 Phase 3 → qps-peak-finder-analysis
2. **🟠 H20 生产锚点补测**（endpoint 确认后）
3. **🟡 EVAL_REPORT.md 追加 Eagle3 章节**
4. **🟡 ziwei / lingyu EVAL_REPORT.md**（Step 7）

---

# 会话报告 - 2026-03-24 下午场（17:00~19:00）

## 📌 会话概览

- **开始时间**：2026-03-24 17:00
- **结束时间**：2026-03-24 ~19:00（单点探测仍后台运行）
- **主要目标**：修正 EVAL_REPORT H20 数据 + 分析 Phase 2 进展 + 重启服务后单点探测
- **Git 分支**：main
- **当前提交**：8ae4a49

## ✅ 成果

1. **EVAL_REPORT.md H20 数据三处修正**（`results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md`）
   - §4.2 服务端承载并发：`70（Phase 1 con70 不存在）` → `57（Phase 3 L=λW 实测）`
   - §4.2 peak decode 吞吐：单行混用 → 拆为 Phase 1（1056.7 tok/s）+ Phase 3 ideal档（1260.3 tok/s）
   - §4.4 注释：删除"两者相近"错误说法，区分 L20（差4%准确）vs H20（差50%保守），加 ⚠️ 说明

2. **EAGLE3 4×H20 Phase 2 进展分析**
   - Round 1（0.3415 req/s）：✅ PASS，E2E P90=44.8s，avg_output_len=2221 tokens
   - Round 2（0.4519 req/s）：❌ 异常过载，#running-req=144，E2E≈320s（陡崖型拐点）
   - 诊断：EAGLE3 真实 ideal_rps 预估在 **0.38~0.42 req/s**（远低于 vanilla 的 0.5878）
   - 137 个 status=-5 超时是末尾 in-flight 截断，非服务质量问题

3. **服务重启 + 单点探测启动**
   - Kill Phase 2 进程（bash + python 子进程）
   - 用户更新服务参数，确认在线后重启探测
   - 单点探测 RPS=0.5878（PID 1218813）正在运行，日志：`logs/eagle3-4h20-probe-rps0.5878_20260324_1758/probe.log`

## 🔧 文件变更

| 文件 | 操作 | 关键修改 |
|------|------|---------|
| `results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md` | 修正 | §4.2 承载并发 70→57；吞吐拆行；§4.4 注释修正 |
| `progress.md` | 追加 | 本次会话工作日志 |
| `project_status.md` | 追加 | 本次会话状态报告 |

## 🐛 问题与解决方案

| 问题 | 根因 | 解决 |
|------|------|------|
| 单点探测第一次失败（404 Not Found） | 服务更新未完成上线，路由不存在 | `curl /health` + 冒烟请求确认在线后重启 |
| Phase 2 rps0.4519 服务端 144 并发异常 | 0.4519 req/s 超过 EAGLE3 稳定边界，陡崖拐点特性导致 E2E 从 44.8s 暴涨到 320s | 属于正常过载检测，等待 Phase 2 自动标记 FAIL 并下调 RPS |

## 🎯 技术决策

1. **EAGLE3 陡崖特性确认**：con=60 E2E P90=173s（SLA边界），0.3415 vs 0.4519 之间存在极陡的拐点；下一轮搜索 ~0.393 req/s 是合理锚点
2. **EVAL_REPORT 承载并发取 Phase 3 实测值**：Phase 1 估算值（保守）≠ 实际运行并发，统一以 Phase 3 L=λW 为准
3. **单点探测先于 Phase 2 完整重跑**：服务重启参数未知，先用 vanilla ideal_rps（0.5878）探测服务能力边界，再决定是否重新启动 Phase 2

## ⚠️ 未完成事项

1. **🟠 单点探测 rps0.5878 结果待解析**（~19:00 完成，PID 1218813）
2. **🟠 根据探测结果决定 Phase 2 是否需要重跑**（若 0.5878 通过则可能重设参数；若失败则 ideal_rps 仍在 0.38~0.42 区间）
3. **🟡 EAGLE3 4×H20 Phase 3 待执行**（需 Phase 2 收敛结果）
4. **🟡 EVAL_REPORT.md EAGLE3 章节未追加**（需 Phase 2+3 数据）
5. **🟡 ziwei / lingyu Step 7 EVAL_REPORT 未执行**

## 💡 建议与注意事项

1. **观察 0.5878 探测的 #running-req**：若服务端并发稳定在 50~80，说明服务重启参数有效；若仍爬到 100+，说明 EAGLE3 本身在该 RPS 下不稳定
2. **Phase 2 重跑 INIT_HI 建议**：若 0.5878 通过 SLA，可重设 `INIT_HI=0.5878, INIT_LO=0.3415` 继续精查；若失败，沿用 `INIT_HI=0.4519, INIT_LO=0.3415`
3. **末尾 in-flight 截断问题**：rps0.3415 的 9.12% 超时是框架行为，不影响 SLA 判定，但需确认 Phase 2 脚本不会因此将其误判为 FAIL

## 📈 下次会话计划

1. **🟠 解析 rps0.5878 单点探测结果** → 判断服务更新效果
2. **🟠 根据结果选择路径**：
   - 若 PASS → 重启 Phase 2（调高 INIT_HI 至 0.5878）
   - 若 FAIL → Phase 2 继续从 0.3415~0.4519 区间搜索（下一档 ~0.393）
3. **🟠 Phase 2 收敛后 → Phase 3 网格验证**
4. **🟠 Phase 3 完成后 → qps-peak-finder-analysis 生成 EAGLE3 REPORT.md**
5. **🟡 EVAL_REPORT.md 追加 EAGLE3 章节**
6. **🟡 ziwei / lingyu EVAL_REPORT.md**

---

---

# 会话报告 - 2026-03-24 晚场

## 📌 会话概览

- **日期**: 2026-03-24
- **主要目标**: 对 chart-32b Agent 框架调用记录中的 `prompt2` 进行批量转换，还原完整 messages
- **Git 分支**: main
- **当前提交**: 8ae4a49

## ✅ 成果

### 1. 数据结构分析与转换接口验证

- **数据文件**：`datas/xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl`（40,315 条）
- Agent 框架调用记录：`role=a.prompt = []`（空），`role=a.prompt2` 含结构化输入参数
- 转换接口 `http://172.21.8.42:1324/v1/chat/completions/messages` 可接收 `prompt2` JSON，返回 `{"messages": [system_msg, user_msg]}`
- **Demo 验证通过**：system 长度 ~2619 字符（含动态星盘相位数据），user message 也经过模板化

### 2. 批量转换脚本开发与启动

- **脚本**：`scripts/data/convert_chart_agent_prompt2.py`（新建）
- **设计要点**：5 并发线程池、3 次重试指数退避、有序写出 buffer、断点续传（行数统计）
- **冒烟测试**：20/20 成功 ✅
- **后台任务**：PID 1200975，已持续运行至 19:46
- **当前进度**：5,956 条 / 40,315 条（14.6%），速率 0.75~0.84 条/s，错误仅 1 条

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/data/convert_chart_agent_prompt2.py`（新建） | 创建 | 批量 prompt2 转换脚本 |
| `datas/output_chart/xinghan-chart-32b-v1-1-agent_calls_converted.jsonl` | 生成中 | 已写出 5,956 行 |
| `datas/output_chart/xinghan-chart-32b-v1-1-agent_calls_errors.jsonl` | 生成中 | 当前 1 条错误 |
| `logs/convert_chart_agent_prompt2.log` | 生成中 | 进度日志 |
| `progress.md` | 追加 | 本次会话工作日志 |
| `project_status.md` | 追加 | 本次会话状态报告 |

## 🐛 问题与解决方案

| 问题 | 根因 | 解决 |
|------|------|------|
| 冒烟测试 `exec(code)` 报 `__file__` 未定义 | `exec()` 上下文无 `__file__` | 改用内联 Python 片段独立测试 |
| 进程启动后日志文件为空 | Python 重定向缓冲 + `REPORT_EVERY=200` | `flush=True` 已加；200 条后日志正常 |

## 🎯 技术决策

1. **输出格式选择**：在原始记录基础上填充 `role=a.prompt`（而非单独输出 `{id, messages}`），保留完整原始结构，便于后续数据管道复用
2. **有序写出设计**：使用 `buffer + write_ptr` 而非直接 append，确保输出 JSONL 行顺序与输入一致
3. **断点续传**：通过统计 output + error 文件行数推算已处理条数，无需维护独立 checkpoint 文件

## ⚠️ 未完成事项

1. **prompt2 转换任务进行中**（PID 1200975）：预计约 13 小时后完成（明天早上）
   - 监控：`wc -l datas/output_chart/xinghan-chart-32b-v1-1-agent_calls_converted.jsonl`
   - 日志：`tail -f logs/convert_chart_agent_prompt2.log`
   - 续传：若中断，重新执行 `python3 scripts/data/convert_chart_agent_prompt2.py` 即可
2. Eagle3 4×H20 Phase 2 尚在进行中
3. guoxue EVAL_REPORT.md Eagle3 章节未追加
4. ziwei / lingyu Step 7 EVAL_REPORT 未执行

## 📊 模型评估完整状态表（更新至 2026-03-24 晚）

| 模型 | 硬件 | ideal_rps | QPS 评估 | 回放测试 | EVAL_REPORT | 整体状态 |
|------|------|-----------|---------|---------|-------------|---------|
| xinghan-hepan-72b-v1-2 | 8×L20 | — | ✅ | ✅ | ✅ | 🟢 已交付 |
| xinghan-chart-32b-v1-1-agent | 8×L20 | 7.61 req/s | V1存疑 | V1存疑 | 挂起 | 🔴 重新评估中（数据转换中）|
| tianji-querysafety-4b-v2-3 | 4TP×8实例 | 7.86 RPS | ✅（Phase3缺2档）| ✅ 100% | 待补档 | 🟡 基本完成 |
| xinghan-ziwei-32b-v1 | 8×L20×2实例 | 1.59 req/s | ✅ | ✅ | ❌ 待 Step 7 | 🟡 待报告 |
| xinghan-guoxue-72b-v1-2-reason（vanilla）| 8×L20 / 4×H20 | L20:0.2114 / H20:0.5878 | ✅ | ✅ 两轮 99.89% | ✅ V2 | 🟡 H20锚点待补 |
| xinghan-guoxue-72b-v1-2-reason（Eagle3 8×L20）| 8×L20 | 0.3169 req/s | ✅ 三阶段全完成 | — | ❌ 待追加 | 🟡 报告完成，EVAL待更新 |
| xinghan-guoxue-72b-v1-2-reason（Eagle3 4×H20）| 4×H20 | 进行中 | 🔄 Phase 2 进行中 | — | — | 🔄 评估中 |
| lingyu-235b-A22b-v9-2 | — | — | ✅ | ❌ | ❌ 待 Step 7 | 🟡 待报告 |

## 📈 下次会话计划（优先级）

1. **🔄 确认 prompt2 转换任务完成**（若明天早上完成）→ 核查转换结果 → 后续 chart 数据处理
2. **🟠 确认 Eagle3 4×H20 Phase 2 收敛结果** → 执行 Phase 3 → qps-peak-finder-analysis
3. **🟠 H20 生产锚点补测**（endpoint 确认后）
4. **🟡 guoxue EVAL_REPORT.md 追加 Eagle3 章节**
5. **🟡 ziwei / lingyu EVAL_REPORT.md**（Step 7）

---

# 会话报告 - 2026-03-25（下午场）

## 📌 会话概览

- **日期**：2026-03-25
- **主要目标**：对新跑完的两个 rps=0.5878 探针执行 benchmark-result-analysis，并通过 brainstorming 梳理报告体系一致性
- **Git 分支**：main（ahead 1 commit）

---

## ✅ 成果

### 1. 两个探针分析报告（新建）

| 报告 | 结论 |
|------|------|
| `results/guoxue-v2-4h20-probe-infra-base-20260325/REPORT.md` | ⚠️ 100% 成功，E2E P90=189.6s 略超 SLA（共享负载所致），TTFT/TTFS 达标 |
| `results/guoxue-v2-eagle3-4h20-probe-infra-opti-20260325/REPORT.md` | ❌ 成功率 75.15%，E2E P90=600.6s，过载二次确认，max RPS≈0.52 |

### 2. 报告体系对齐（四份文件更新）

| 文件 | 核心改动 |
|------|---------|
| `logs/.../qps_0.5878/README.md` | 补 TTFS P90=635ms，新增 infra-base 对比表 + 双向指针 |
| `results/guoxue-v2-h20-peak-finder-20260323/REPORT.md` | 新增 §5 生产端点观测补充 |
| `results/models/.../EVAL_REPORT.md` | §4.2 并发拆行（极限230/理想57）；§4.3 TTFT/TTFS 分列修正；新增 §4.6 |
| `results/models/.../model-context.md` | 并发字段拆分 + 11 个 infra-base 探针字段 |

### 3. 数据治理决策确立

- 新探针**独立目录保留**，通过 README 交叉引用连接 Phase 3，不混入原始数据
- Phase 3 直连 API 结论（ideal_rps=0.5878）维持权威，infra-base 作生产观测附注

---

## 🔧 文件变更

| 文件路径 | 变更类型 | 说明 |
|---------|---------|------|
| `logs/guoxue-v2-h20-phase23_merged_20260323/qps_0.5878/README.md` | 更新 | 补 TTFS，新增生产端点对比节 |
| `logs/guoxue-v2-4h20-probe-rps0.5878_20260325_1140/README.md` | 新建 | 探针快速结论 + 结果指针 |
| `logs/eagle3-4h20-probe-rps0.5878_20260325_1156/README.md` | 新建 | Eagle3 探针结论（过载二次确认）|
| `results/guoxue-v2-4h20-probe-infra-base-20260325/REPORT.md` | 新建 | Vanilla infra-base 完整分析报告 |
| `results/guoxue-v2-4h20-probe-infra-base-20260325/*.png` | 新建 | 7 张 CDF/Timeline PNG |
| `results/guoxue-v2-4h20-probe-infra-base-20260325/probe_rps0.5878_analysis.html` | 新建 | 交互式 HTML 报告 |
| `results/guoxue-v2-eagle3-4h20-probe-infra-opti-20260325/REPORT.md` | 新建 | Eagle3 infra-opti 完整分析报告 |
| `results/guoxue-v2-eagle3-4h20-probe-infra-opti-20260325/*.png` | 新建 | 7 张 CDF/Timeline PNG |
| `results/guoxue-v2-h20-peak-finder-20260323/REPORT.md` | 更新 | 新增 §5 生产端点观测（138→162行）|
| `results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md` | 更新 | §4.2/§4.3/§4.6 三处修正（246→261行）|
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | 更新 | 并发字段拆分 + probe 字段（159→176行）|
| `results/README.md` | 更新 | 新增两条探针实验索引 |

---

## 🐛 问题与解决方案

| 问题 | 根因 | 解决 |
|------|------|------|
| `StrReplace` 替换失败（REPORT.md 上线建议表）| 原表用 `\|\|` 前缀格式，匹配字符串有偏差 | Python `content.replace()` + `repr()` 调试 |
| EVAL_REPORT.md H20 表替换失败（首次）| 表格 pipe 格式与预期有细微差异 | `repr()` 打印实际内容后精确构造匹配串 |
| §4.6 超链接格式错误（反引号而非链接）| 插入时沿用了代码块写法 | 用户指出后立即 `StrReplace` 修正 |

---

## 🎯 技术决策

1. **探针数据不合并入 Phase 3**：两次测试端点、数据集、背景负载均不同，合并会导致分位数失真；采用交叉引用代替物理合并
2. **infra-base E2E 超标定性为"部署层问题"**：Decode 吞吐持平（1248 vs 1260 tok/s），背景流量 +26 并发完全解释 E2E 增量，ideal_rps 基准不受影响
3. **TTFT/TTFS 口径在三层文档中统一**：README → REPORT.md → EVAL_REPORT.md 全部拆分为独立两列

---

## 💡 关键洞察（供下次会话参考）

1. **Eagle3 4×H20 两次过载（3-24 和 3-25）**共同规律：Decode 吞吐低于 Vanilla（1157~1224 vs 1260 tok/s），加上 avg_output_len 略高，导致 max sustainable RPS ≈ 0.52 < 0.5878。若要测试 Eagle3 合理 RPS，建议从 **0.45 req/s** 开始探针
2. **infra-base 端点命名变化**：Phase 3 使用 `infra-xinghan-guoxue-p72b-v12-reason`，当前生产为 `infra-base-xinghan-guoxue-p72b-v12-reason`，两者指向同一服务实例（用户确认）
3. **Grafana 部署名**：Vanilla H20 对应 `xinghan-guoxue-p72b-v12-reason-h20-tp4-base`（带 `-base` 后缀），与旧名 `xinghan-guoxue-p72b-v12-reason-h20-tp4` 不同

---

## ⚠️ 未完成事项

1. **Eagle3 4×H20 调整后探针结果分析**：`eagle3-4h20-probe-rps0.5878_20260325_1156` 已完成，待离线分析
2. **Eagle3 2TP RPS=0.3 探针结果分析**：`eagle3-2tp-probe-rps0.3_20260325_1422` 运行中，待结果
3. **infra-base 严格基线**：若需精确测 infra-base 容量，需在独占资源（无背景流量）时段重跑
4. **guoxue EVAL_REPORT.md Eagle3 4×H20 章节**：当前 EVAL_REPORT 尚无 Eagle3 4×H20 的专属评估章节
5. **ziwei / lingyu EVAL_REPORT.md**（Step 7）：仍未执行
6. **chart-32b 数据转换**：`convert_chart_agent_prompt2.py` 转换任务状态待确认

---

## 📊 模型评估完整状态表（更新至 2026-03-25 下午）

| 模型 | 硬件 | ideal_rps | QPS 评估 | 回放测试 | EVAL_REPORT | 整体状态 |
|------|------|-----------|---------|---------|-------------|---------|
| xinghan-hepan-72b-v1-2 | 8×L20 | — | ✅ | ✅ | ✅ | 🟢 已交付 |
| xinghan-chart-32b-v1-1-agent | 8×L20 | 7.61 req/s | V1存疑 | V1存疑 | 挂起 | 🔴 重新评估中 |
| tianji-querysafety-4b-v2-3 | 4TP×8实例 | 7.86 RPS | ✅ | ✅ 100% | 待补档 | 🟡 基本完成 |
| xinghan-ziwei-32b-v1 | 8×L20×2实例 | 1.59 req/s | ✅ | ✅ | ❌ 待 Step 7 | 🟡 待报告 |
| xinghan-guoxue-72b-v1-2-reason (Vanilla 8×L20) | 8×L20 | 0.2114 req/s | ✅ | ✅ 两轮 99.89% | ✅ V2 | 🟢 完成 |
| xinghan-guoxue-72b-v1-2-reason (Vanilla 4×H20) | 4×H20 | **0.5878 req/s** | ✅ Phase1~3 全完成 | ✅ 两轮 | ✅（含 §5 补充）| 🟢 完成（infra-base 探针已附注）|
| xinghan-guoxue-72b-v1-2-reason (Eagle3 8×L20) | 8×L20 | 0.3169 req/s | ✅ 三阶段 | — | ❌ 待追加章节 | 🟡 报告完成待 EVAL 更新 |
| xinghan-guoxue-72b-v1-2-reason (Eagle3 4×H20，调整后) | 4×H20 | **待分析** | 探针完成（0.5878） | — | — | 🟡 待离线分析 |
| xinghan-guoxue-72b-v1-2-reason (Eagle3 2TP) | 2×H20? | **待分析** | 探针运行中（0.3） | — | — | 🔄 进行中 |
| lingyu-235b-A22b-v9-2 | — | — | ✅ | ❌ | ❌ 待 Step 7 | 🟡 待报告 |

---

## 🗓️ 本次会话（2026-03-25 下午场续）工作摘要

### 启动的探针任务

| 编号 | 端点 | 部署 | RPS | 请求数 | PID | 日志目录 | 状态 |
|------|------|------|-----|--------|-----|---------|------|
| 1 | infra-base（vanilla H20） | 4TP | 0.5878 | 2117 | 1953463 | `guoxue-v2-4h20-probe-rps0.5878_20260325_1140` | ✅ 完成 |
| 2a | infra-opti（Eagle3 4H20，初次） | 4TP | 0.5878 | 2117 | 1958187 | `eagle3-4h20-probe-rps0.5878_20260325_1145` | ❌ 提前终止（服务端异常）|
| 2b | infra-opti（Eagle3 4H20，调整后）| 4TP | 0.5878 | 2117 | 1966237 | `eagle3-4h20-probe-rps0.5878_20260325_1156` | ✅ 完成 |
| 3 | infra-opti（Eagle3 2TP） | 2TP | 0.3 | 1080 | 2075568 | `eagle3-2tp-probe-rps0.3_20260325_1422` | 🔄 运行中 |

### 关键背景
- 任务 1：`infra-base` 端点对应 Vanilla H20 4TP 部署，RPS=0.5878 为已知 ideal_rps，本次为生产网关二次确认
- 任务 2b：用户调整了 Eagle3 4×H20 服务端配置后重测，结果待分析
- 任务 3：用户将 `infra-opti` 端点切换为 **2TP 部署**，用 RPS=0.3 初步验证（约为 4TP ideal_rps 的 50%），符合 2TP 理论吞吐折半的预期

---

## 📈 下次会话计划（优先级）

1. **🔴 Eagle3 4×H20（调整后）探针离线分析**：对 `eagle3-4h20-probe-rps0.5878_20260325_1156` 跑 `analyze_peak_finder.py`，判断是否 SLA 达标
2. **🔴 Eagle3 2TP RPS=0.3 探针结果分析**：对 `eagle3-2tp-probe-rps0.3_20260325_1422` 分析，确认 2TP 部署实际承载能力
3. **🟠 根据上述结果更新 guoxue EVAL_REPORT.md**：追加 Eagle3 4×H20 调整后 + 2TP 评估章节
4. **🟡 ziwei / lingyu EVAL_REPORT.md** Step 7
5. **🟡 chart-32b-agent benchmark（Phase 1~3）完成后**：
   - 执行 `scripts/migrate_chart_outputs.sh` 迁移 `output_chart_agent/`
   - 执行 `mv chart-32b-agent-* peak_finder_chart_agent_*.log xinghan-chart-32b-v1-1-agent/` 迁移 logs
   - 使用 `qps-peak-finder-analysis` Skill 分析结果，生成 REPORT.md

---

## 📋 会话报告 — 2026-03-25（工程整理专场）

### 📌 会话概览

- **日期**：2026-03-25
- **主要目标**：数据路径迁移后的 skill 对齐检查 + `logs/` 目录层级化改造
- **并行背景任务**：xinghan-chart-32b-v1-1-agent 8TP & 4TP QPS benchmark（Phase 1~3）仍在运行中

---

### ✅ 本次会话成果

#### 1. Skill 数据路径对齐（`traffic-dataset-prep` 补充）

检查确认 `datas/output_*/` 已全部软链接至 `/mnt/ai-infra/datasets/used4evaluation/`，路径对 benchmark 脚本和 skill 透明。唯一需要补充的是：

- **`traffic-dataset-prep` `.env` 参数表**中新增 `agent_converted` 格式说明
  - 适用场景：Agent 框架调用，prompt2 已由外部脚本（`convert_chart_agent_prompt2.py`）预转化为 messages，不走 indexed/DataConverter 流程
  - 典型模型：`xinghan-chart-32b-v1-1-agent`
  - 文件：`clingo/docs/skills/traffic-dataset-prep/SKILL.md`（与 `.cursor/skills/` 同一 inode）

#### 2. `logs/` 目录层级化

**新结构**：
```
logs/
├── xinghan-chart-32b-v1-1-agent/    ← 空（待 chart benchmark 完成后迁入）
├── xinghan-guoxue-72b-v1-2-reason/  ← 25 个实验目录
├── xinghan-ziwei-32b-v1-1/          ← 6 个实验目录
├── tianji-querysafety-4b-v2-3/      ← 5 个实验目录
├── lingyu-235b-A22b-v9-2/           ← 1 个实验目录
├── chart-32b-agent-*（4个，运行中） ← 待迁入
├── peak_finder_chart_agent_*.log     ← 待迁入
├── data-pipeline/                    ← 共享，不加模型层
└── archive/                          ← 共享，暂不动
```

**约定**：
- `MODEL_NAME` = 完整模型名（算法提供）→ `logs/` 第一层子目录
- `MODEL` = 实验短名 → 实验目录名前缀

#### 3. 6 个 Skill 路径模板批量更新

统一路径规则 `logs/<exp>/` → `logs/<model-full-name>/<exp>/`，涉及：

| Skill | 核心变更 |
|-------|---------|
| `qps-peak-finder` | Phase 1/3 `OUTPUT_DIR` 加 `${MODEL_NAME}/` 层，注释说明两变量含义 |
| `qps-peak-finder-analysis` | 合并目录 `MERGED`、Phase 2/3 glob 路径、YAML config `dir` 字段 |
| `qps-benchmark-sweep` | 监控命令、合并目录、历史案例、README 写入路径 |
| `llm-replay-benchmark` | `OUTDIR`、console log 改入 `data-pipeline/`、README 写入路径 |
| `benchmark-result-analysis` | 前置条件、`--csv` 示例、`compare_analysis.py` 示例 |
| `model-evaluation-workflow` | skip 检查 glob、实验 README 路径、archive 注意事项 |

---

### 🗂️ 项目基础设施当前状态

| 组件 | 状态 | 说明 |
|------|------|------|
| `datas/` | ✅ 软链接完成 | 实体在 `used4evaluation/`，datas/ 下全为软链接 |
| `logs/` | ✅ 层级化完成 | chart-32b-agent 4个目录待 benchmark 结束后手动迁入 |
| Skills（6个）| ✅ 路径模板更新 | `logs/<model-full-name>/<exp>/` 规范已统一 |
| `migrate_chart_outputs.sh` | ⏳ 待执行 | chart benchmark 结束后运行 |

---

### ⚠️ 待办事项（跨会话）

1. **chart-32b-agent benchmark 完成后**（预计今日内）：
   ```bash
   # 1. 迁移 output 数据目录
   bash scripts/migrate_chart_outputs.sh
   # 2. 迁移 logs 实验目录
   cd logs && mv chart-32b-agent-* peak_finder_chart_agent_*.log xinghan-chart-32b-v1-1-agent/
   ```
2. **guoxue Eagle3 探针分析**（优先级最高）：2 个探针实验待分析
3. **chart-32b-agent 评估分析**：Phase 1~3 完成后运行 `qps-peak-finder-analysis` Skill

---

## 会话报告 - 2026-03-25 下午场

### 📌 会话概览
- **开始时间**: 2026-03-25 17:51（发现 Phase 1 异常）
- **结束时间**: 2026-03-25 19:05
- **主要目标**: 排查 chart-32b-agent 4TP/8TP Phase 1 中断原因，补全 Phase 1，启动 Phase 2
- **Git 分支**: main（uncommitted changes）

### ✅ 成果总览

| 任务 | 状态 |
|------|------|
| 排查 bash 增量读取导致 EOF 错误根因 | ✅ |
| 8TP Phase 1 完整分析（饱和于 con=410）| ✅ |
| 4TP Phase 1 补跑 con=480（饱和于 con=480）| ✅ |
| 7 个 chart agent 脚本路径修复 | ✅ |
| analyze_peak_finder.py checkpoint bug 修复 | ✅ |
| 8TP Phase 2 启动（rps=5.4592）| ✅ 运行中 |
| 4TP Phase 2 启动（rps=4.3212）| ✅ 运行中 |

### 🔧 文件变更

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `scripts/benchmark/run_peak_finder_chart_agent.sh` | 🔧 路径修复 | SESSION_DIR 加 `xinghan-chart-32b-v1-1-agent/` 前缀 |
| `scripts/benchmark/run_phase1_auto_chart_agent_4tp.sh` | 🔧 路径修复 | OUTPUT_BASE 路径更新 |
| `scripts/benchmark/run_phase1_auto_chart_agent_8tp.sh` | 🔧 路径修复 | OUTPUT_BASE 路径更新 |
| `scripts/benchmark/run_phase2_auto_chart_agent_4tp.sh` | 🔧 路径修复 | OUTPUT_BASE 路径更新 |
| `scripts/benchmark/run_phase2_auto_chart_agent_8tp.sh` | 🔧 路径修复 | OUTPUT_BASE 路径更新 |
| `scripts/benchmark/run_phase3_grid_chart_agent_4tp.sh` | 🔧 路径修复 | OUTPUT_BASE 路径更新 |
| `scripts/benchmark/run_phase3_grid_chart_agent_8tp.sh` | 🔧 路径修复 | OUTPUT_BASE 路径更新 |
| `scripts/analysis/analyze_peak_finder.py` | 🐛 bug 修复 | `_write_phase1_checkpoint()` 签名拆分为 phase0/measured 两个参数 |

### 📊 benchmark 当前状态

#### 4TP — Phase 1 ✅ 完成
| 并发 | 吞吐 | 增幅 |
|------|------|------|
| con=25 | 546.4 t/s | — |
| con=50 | 862.6 t/s | +57.87% |
| con=100 | 1279.7 t/s | +48.35% |
| con=200 | 1470.9 t/s | +14.94% |
| con=400 | **1627.7 t/s** ← 峰值 | +10.66% |
| con=480 | 1567.3 t/s | **-3.71% ✅ 饱和** |

- peak_rps（Phase 0 avg=452）= **3.60 req/s**
- Phase 2 START_RPS = **4.32 req/s**，进程 pid 2301413，运行中

#### 8TP — Phase 1 ✅ 完成
| 并发 | 吞吐 | 增幅 |
|------|------|------|
| con=50 | 1211.0 t/s | — |
| con=100 | 1706.0 t/s | +40.87% |
| con=200 | 1955.4 t/s | +14.62% |
| con=400 | **2056.8 t/s** ← 峰值 | +5.18% |
| con=410 | 2055.9 t/s | **-0.04% ✅ 饱和** |

- peak_rps（Phase 0 avg=452）= **4.55 req/s**
- Phase 2 START_RPS = **5.46 req/s**，进程 pid 2266194，运行中（自 18:19）

#### 关键横向对比
- 8TP/4TP 峰值吞吐比 = 2057/1628 ≈ **1.26x**（远低于理论 2x）
- 说明 32B 模型从 4TP 扩展到 8TP 存在显著通信开销，上线建议需结合成本考量

### 🗂️ 目录结构现状

```
logs/
├── xinghan-chart-32b-v1-1-agent/
│   ├── chart-32b-agent-4tp-phase1_20260325_1541/   ✅ Phase 1 完成（con25~480）
│   ├── chart-32b-agent-4tp-session_20260325_1541/  （旧 session，已废弃）
│   ├── chart-32b-agent-8tp-phase1_20260325_1541/   ✅ Phase 1 完成（con50~410）
│   ├── chart-32b-agent-8tp-session_20260325_1541/  （旧 session，已废弃）
│   ├── chart-32b-agent-4tp-phase2_20260325_1900/   ⏳ Phase 2 运行中
│   └── chart-32b-agent-8tp-phase2_20260325_1819/   ⏳ Phase 2 运行中
└── data-pipeline/
    ├── peak_finder_chart_agent_4tp_console.log     nohup 日志
    └── peak_finder_chart_agent_8tp_console.log     nohup 日志
```

### 💡 技术决策

1. **bash 脚本增量读取陷阱**：长时间等待外部进程时，不要在脚本运行期间编辑该脚本文件；若必须，应在外部进程结束后再编辑
2. **路径规范统一**：所有 chart agent 脚本输出路径统一为 `logs/xinghan-chart-32b-v1-1-agent/chart-32b-agent-*`
3. **Phase 2 参数选用 Phase 0 权威 avg_output_len（452 tokens）**：Phase 1 实测值（473-477 tokens）存在截断偏差，与 Phase 0 偏差 ~5%（≤20% 阈值），使用 Phase 0 值计算 max_rps

### ⚠️ 下次会话需关注

1. **Phase 2 进度监控**（每档约 30min）：
   ```bash
   tail -f logs/data-pipeline/peak_finder_chart_agent_4tp_console.log
   tail -f logs/data-pipeline/peak_finder_chart_agent_8tp_console.log
   ```
2. **Phase 2/3 完成后**运行 `qps-peak-finder-analysis` Skill 生成 REPORT.md
3. **注意 Phase 2 SLA 判定**：TTFS P90 ≤ 1500ms，E2E P90 ≤ 150s
4. **若 Phase 2 首档即失败**（rps=4.32/5.46 超载），检查 production_rps 设置（当前脚本是否设了合理的下界）

---

## 📦 2026-03-25 下午场（第二轮）— analyze_peak_finder.py 全面加固

### 📌 本轮会话概览

- **主题**：修复 `analyze_peak_finder.py` Phase 0/Phase 1 分析逻辑中遗留的 5 个问题，并补全 10 个 auto 脚本的调用链
- **Git 分支**：main（本地 ahead 1）
- **最新提交**：`8ae4a49`

### ✅ 本轮完成事项

| 编号 | 修改点 | 涉及文件 |
|------|--------|---------|
| 1 | Phase 0 tokenize 从 500 条采样改为全量 | `analyze_peak_finder.py` |
| 2 | Phase 0 添加 `<think>` 比例 + `<con>` 残留质量检查 | `analyze_peak_finder.py` |
| 3 | Phase 0 输出 DURATION_SECS / COOLDOWN_SECS / INIT_CON 推算结果 | `analyze_peak_finder.py` |
| 4 | Phase 1 新增 `--avg-output-len-phase0` 参数，优先用 Phase 0 值作 max_rps 分母 | `analyze_peak_finder.py` |
| 5 | Phase 1 checkpoint 新增双值对比行（Phase 0/Phase 1 偏差、用于计算的分母来源） | `analyze_peak_finder.py` |
| 6 | SKILL.md 更新 Phase 1 CLI 用法和 checkpoint 模板 | `clingo/docs/skills/qps-peak-finder/SKILL.md` |
| 7 | 10 个 Phase 1 auto 脚本补传 `--avg-output-len-phase0` | 见下表 |

**修改的 auto 脚本（共 10 个）**：

| 脚本 | AVG_OUTPUT_LEN | 备注 |
|------|---------------|------|
| `run_phase1_auto_chart4tp.sh` | 200 | 加参数 |
| `run_phase1_auto_chart8tp.sh` | 200 | 加参数 |
| `run_phase1_auto_chart_agent_4tp.sh` | 452 | 加参数 |
| `run_phase1_auto_chart_agent_8tp.sh` | 452 | 加参数 |
| `run_phase1_auto_tianji4tp_bakv1.sh` | 14 | 加参数 |
| `run_phase1_auto_ziwei8tp.sh` | 180 | 加参数 |
| `run_phase1_auto_guoxue8tp_v2.sh` | 2157 | 加参数 |
| `run_phase1_auto_guoxue_eagle3.sh` | 2142 | 加参数 |
| `run_phase1_auto_guoxue_eagle3_4h20.sh` | 2204 | 加参数（变量名为 `AVG_OUTPUT_LEN_PHASE0`）|
| `run_phase1_auto_guoxue4h20.sh` | **新增** 2204 | 补变量 + 加参数 |

### 🎯 技术决策

1. **Phase 0 全量 tokenize**：对 5~50K 行的数据集，500 条采样误差可达 20%+，必须全量；对超大数据集（>100K）将来可考虑加 `--max-sample` 上限
2. **Phase 0 数据质量阈值**：`<think>` ≥ 70% 为合格（允许少量非推理链响应混入），`<con>` < 5% 为合格（允许极少量历史格式残留）
3. **`--avg-output-len-phase0` 非必填**：回落到 Phase 1 实测值并打 ⚠️，确保兼容旧脚本；未来新脚本应始终传此参数
4. **guoxue4h20 AVG_OUTPUT_LEN=2204**：与 eagle3_4h20 同数据集同模型，Phase 0 原始值 1386 有已知数据缺陷（缺少推理链），使用 Phase 1 实测值 2204

### 📊 当前进行中的压测

| 模型 | TP | 阶段 | 状态 | 关键参数 |
|------|-----|------|------|---------|
| chart-32b-agent | 4TP | Phase 2 | ⏳ 运行中（pid 2301413）| PEAK_RPS=3.60, START_RPS=4.32 |
| chart-32b-agent | 8TP | Phase 2 | ⏳ 运行中（pid 2266194）| PEAK_RPS=4.55, START_RPS=5.46 |

### ⚠️ 下次会话需关注

1. **Phase 2/3 结果**：两路 Phase 2 仍在运行，完成后执行 `qps-peak-finder-analysis` Skill 生成 REPORT.md
2. **新模型 Phase 0 最佳实践**：下次新模型接入时，按新 Phase 0 流程：全量 tokenize → 质量检查 → 复制推算参数
3. **guoxue4h20 尚无完整 Phase 0**：当前 AVG_OUTPUT_LEN=2204 来自 eagle3_4h20 实测值，如需权威值应重新对 4H20 数据集跑 Phase 0（需先确认 old_response 已含完整推理链）

---

## 📦 2026-03-26 晚间场 — chart-deep-v5-2-235B relay 修复 + Phase 2 启动

### 📌 本轮会话概览

- **主题**：诊断并修复 `watch_and_relay` 脚本两个 bug，清理重复进程，成功启动 chart-deep-v5-2-235B 8×H20 的干净 Phase 2
- **Git 分支**：main（本地 ahead 1，commit `67444cc`）
- **涉及模型**：`chart_deep_v5-2_235B_chart_deep`（8×H20）
- **数据集**：`datas/output_chart-deep-v5/combined_extracted.csv`（5621 条）

### ✅ 本轮完成事项

#### Phase 1 已完成（上午场遗留）

| 档位 | max_rps_estimate | 吞吐增幅 | 结论 |
|------|-----------------|---------|------|
| con=60 | 0.9708 req/s | — | 未饱和 |
| con=120 | 1.2797 req/s | +31.83% | 未饱和 |
| con=180 | **1.2911 req/s** | +0.89% | ✅ 饱和 |

- **PEAK_RPS = 1.2911**，Phase 2 START_RPS = 1.5493（×1.2）
- SLA：TTFS P90 ≤ 1.5s，E2E P90 ≤ 150s

#### watch_and_relay_chart_deep_8h20.sh — 修复 2 个 Bug

| Bug | 描述 | 修复方案 |
|-----|------|---------|
| Bug 1：提前退出 | checkpoint 文件首次出现（con=60 结束）即 break，Phase 1 仍在跑后续档 | 增加检查 Phase 1 run log 中 `NEXT_CON=SATURATED` 标志 |
| Bug 2：grep 解析失败 | checkpoint 为 Markdown 表格格式，旧 grep `=` 模式不匹配，触发 `set -e` 退出 | 改用 `\|\s*max_rps_estimate\s*\|\s*\K` + `\|\| true` + `tail -1` |

#### Phase 2 干净启动（14:41）

- 清理 3 批污染的重复进程 + 2 个中间目录
- 最终只保留一个 Phase 2（PID 3204661）+ relay（PID 3204623）
- 输出目录：`logs/chart-deep-v5-2/chart-deep-v5-2-phase2_20260326_1441/`
- 监控日志：`logs/chart-deep-v5-2/relay_20260326_1441.log`

### 🐛 问题与解决方案

| 问题 | 根因 | 解决 |
|------|------|------|
| relay 12:36 提前退出，Phase 2 未启动 | Bug 1 + Bug 2 | 修复脚本，重新启动 |
| 多个 Phase 2 并发污染（2～3 次） | 手动 + relay 同时启动 Phase 2 | 统一由 relay 管理 Phase 2，严禁手动并发启动 |
| 进程 kill 偶发 `Aborted` | Cursor Shell 限制 | 在服务器终端直接执行 |

### 🎯 技术决策

1. **relay 负责全流程 Phase 2/3 接力，不应手动再启 Phase 2**：relay 的设计是内部 `nohup` 启动 Phase 2，外部再手动启动等于双开
2. **Phase 2 中间结果需清理**：被中断的 rps 档位目录数据不可信，必须删除，避免分析工具误读
3. **Phase 1 PEAK_RPS 仅是吞吐上限，非 SLA 合规点**：服务器在 1.5 RPS 时已现 queue 淤积（#queue-req 达 21~23），Phase 2 从 1.55 RPS 向下收敛符合预期

### 📊 当前进行中任务（20:18 状态）

| 模型 | 阶段 | 档位 | 状态 |
|------|------|------|------|
| chart-deep-v5-2-235B 8×H20 | Phase 2 | rps=1.3582（第 2 轮 bracket） | ✅ 运行中 |
| guoxue Eagle3 4×H20 | 探针调参测试 | rps=0.5878 | ✅ 运行中（18:46 启动） |

### ⚠️ 下次会话需关注

1. **chart-deep Phase 2/3 结果**：
   - Phase 2 预计今晚 19:00～21:00 完成（从 14:41 开始，每档 50min，约 5～8 档）
   - Phase 3 自动触发，完成后运行 `qps-peak-finder-analysis` Skill 生成 REPORT.md
   - 监控：`tail -f logs/chart-deep-v5-2/relay_20260326_1441.log`

2. **Eagle3 4×H20 调参探针结果**：
   - 约 19:46 完成，需用 `analyze_peak_finder.py --phase1` + `offline_analysis.py` 对比新旧探针
   - 对比维度：speculative steps 3→2，draft tokens 4→3，看 TTFS/E2E 是否改善

3. **relay 脚本设计建议**：
   - 添加 `SKIP_PHASE1_WAIT=true` 环境变量，当 Phase 1 已完成时直接跳到 Phase 2 启动逻辑（避免每次手动 debug）
   - 考虑在 Phase 1 脚本末尾 `touch "${PHASE1_DIR}/phase1_done"` 写入 done marker，relay 检查更可靠

4. **chart-deep 分析参数配置**（Phase 2/3 完成后需准备）：
   - PEAK_RPS = 1.2911、PRODUCTION_RPS = 0.5（30 RPM）
   - 配置文件参考：`configs/models/chart-deep-v5-2-235B/8h20.env`

---

## 📅 2026-03-27 会话报告（为下次会话提供上下文）

### 一、会话概览

| 项目 | 内容 |
|------|------|
| 开始时间 | 2026-03-27 上午 |
| 核心任务 | 修复 chart-deep-v5-2-235B 评估受 128 并发限制污染问题，重跑 Phase 1 + Phase 2 |
| 最终状态 | Phase 1 完成（con=326 饱和），Phase 2 新跑进行中（rps=1.4012 冷却后启动） |

### 二、关键发现：128 限制导致全链路低估 ~20%

旧跑（2026-03-26）服务端配置了 `--max-running-requests 128`，导致：

| 指标 | 旧跑（受限） | 新跑（无限制） | 变化 |
|------|------------|--------------|------|
| peak_decode_throughput | 1298.9 tok/s（con=180 假饱和） | **1603.6 tok/s**（con=326 真饱和） | **+23.5%** |
| max_rps_estimate | 1.2911 req/s | **1.5940 req/s** | **+23.5%** |
| 真实饱和并发 | 128（人为截断） | **326** | +155% |
| ideal_rps | 1.3360 req/s（偏保守下界） | 预计 **1.40~1.43 req/s** | 待确认 |
| Phase 3 验证网格 | 基于旧 ideal_rps，结论偏保守 | 新 Phase 3 将在 Phase 2 后重跑 | — |

### 三、已修改的文件

| 文件 | 修改内容 |
|------|---------|
| `scripts/benchmark/run_phase1_auto_chart_deep_8h20.sh` | SERVER_URL 更新为 172.21.65.249；删除 MAX_REQUESTS=5621 硬编码；PREV_DIR 支持环境变量注入；AUTO_PHASE2 触发时透传 INIT_LO |
| `scripts/benchmark/run_phase2_auto_chart_deep_8h20.sh` | SERVER_URL 更新为 172.21.65.249 |
| `scripts/benchmark/run_phase3_grid_chart_deep_8h20.sh` | SERVER_URL 更新为 172.21.65.249 |

### 四、新建产物

| 产物 | 路径 | 说明 |
|------|------|------|
| Phase 1 新跑日志 | `logs/chart-deep-v5-2/phase1_run_20260327_1247.log` | 含 Phase 1 完整进度 + Phase 2 自动触发记录 |
| Phase 1 新跑 checkpoint | `logs/chart-deep-v5-2/chart-deep-v5-2-phase1_20260327_1247/phase1_checkpoint.md` | 6档数据，con=326 饱和，max_rps=1.5940 |
| Phase 2 新跑目录 | `logs/chart-deep-v5-2/chart-deep-v5-2-phase2_20260327_1857/` | 进行中，rps1.4696（FAIL）已完成 |
| rps1.3360 离线分析 HTML | `results/chart-deep-v5-2-phase2-rps1.3360-20260326/chart_deep_phase2_rps1.3360_analysis.html` | 含完整交互图表 |
| rps1.3360 REPORT.md | `results/chart-deep-v5-2-phase2-rps1.3360-20260326/REPORT.md` | 含 128 限制指纹分析，TTFT P99 跳升证据 |
| model-context.md | `results/models/chart-deep-v5-2-235B/model-context.md` | 模型配置 + 阶段性结论结构化记录 |
| 中间评估报告 | `results/models/chart-deep-v5-2-235B/EVAL_REPORT_interim.md` | 完整阶段分析，含旧/新对比表 |

### 五、当前进行中任务（2026-03-27 19:30）

| 进程 | 目录/日志 | 状态 | 预计完成 |
|------|---------|------|---------|
| Phase 2 新跑 | `chart-deep-v5-2-phase2_20260327_1857/` | 🔄 rps=1.4012 冷却中 | ~22:00~22:30 |
| Phase 3（自动触发）| 待创建 | ⏳ Phase 2 完成后触发 | ~次日 01:00 |

**Phase 2 当前 bracket**：LO=1.3360, HI=1.4696，宽度 10%，下探 rps=1.4012

### 六、下次会话启动检查清单

```bash
# 1. 检查 Phase 2 是否完成
cat logs/chart-deep-v5-2/chart-deep-v5-2-phase2_20260327_1857/phase2_checkpoint.md

# 2. 检查 Phase 3 是否启动/完成
ls logs/chart-deep-v5-2/ | grep phase3

# 3. 若 Phase 2/3 已完成，运行 qps-peak-finder-analysis Skill
# 4. 确认业务峰值 RPM（Grafana），更新 model-context.md
# 5. 生成最终 EVAL_REPORT.md
```

### 七、关键参数备忘

| 参数 | 值 | 来源 |
|------|----|----|
| avg_output_len | 1006 tokens | Phase 0 |
| peak_decode_throughput（新） | **1603.6 tok/s** | Phase 1 新跑 con=326 |
| max_rps_estimate（新） | **1.5940 req/s** | Phase 1 新跑 |
| Phase 2 INIT_LO | 1.3360 req/s | 旧 Phase 2 最高 PASS |
| Phase 2 HI（新） | 1.4696 req/s | Phase 2 新跑首档 FAIL |
| Phase 2 下一档（新） | **1.4012 req/s** | √(1.3360×1.4696) |
| PRODUCTION_RPS | 0.5 req/s（30 RPM 保守托底） | 待 Grafana 确认 |
| DURATION_SECS | 2520s | max(1200, int(1006×2.5)) |
| COOLDOWN_SECS | 510s | max(60, int(1006/2)) |

---

# 会话报告 - 2026-03-27（下午场）guoxue Eagle3 4×H20 SLA 边界探针

## 📌 会话概览

- **时间**：2026-03-27 16:00 — 19:10
- **主要目标**：guoxue-72b-v1-2-reason Eagle3 4×H20 服务多档位 SLA 边界定位
- **Git 分支**：main（67444cc）
- **结论**：✅ **ideal_rps = 0.40 req/s（24 RPM）**，SLA 边界区间 `0.40 < ideal_rps < 0.43`

---

## ✅ 成果

### 1. Phase2 rps=0.3415 补充分析
- 确认 rps0.4519 目录为空（EXIT_TRAP 提前退出），仅分析 rps=0.3415
- 结论：成功率 100%，TTFT P90=0.489s，TTFS P90=0.594s，E2E P90=44.8s，SLA 全达标
- 报告：`results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-phase2-20260324/REPORT.md`

### 2. RPS=0.40 探针测试 ✅
- 480 请求，20 分钟，成功率 100%
- E2E P90=107.2s（SLA ≤180s，余量 40%），TTFS P90=0.901s
- 报告：`results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.400-20260327/REPORT.md`

### 3. RPS=0.43 探针测试 ❌（临界超标）
- 516 请求，22 分钟，成功率 100%
- E2E P90=182.1s，超过 SLA 阈值 180s（+1.1%，超 2.1s）
- 报告：`results/guoxue-v2-eagle3/guoxue-v2-eagle3-4h20-probe-rps0.430-20260327/REPORT.md`

### 4. ideal_rps 定位完成
- **`ideal_rps = 0.40 req/s（24 RPM）`**
- 边界区间：`0.40 < ideal_rps < 0.43`

---

## 📊 guoxue Eagle3 4×H20 完整探针记录

| RPS | 成功率 | E2E P90 | 判定 |
|-----|--------|---------|------|
| 0.5878（3-25）| 75.15% | 600.6s | ❌ 严重过载 |
| 0.43 | 100% | 182.1s | ❌ 临界超标 |
| **0.40** | **100%** | **107.2s** | **✅ ideal_rps** |
| 0.3415 | 100% | 44.8s | ✅ |

---

## 🐛 问题与解决

| 问题 | 原因 | 解决 |
|------|------|------|
| 进程残留，多次重启测试 | kill 不彻底，用户在不同 shell 中启动进程 | 每次启动前 pgrep 检查；用户手动清理后重启 |
| rps0.4519 数据缺失 | Phase 2 EXIT_TRAP 提前退出 | 仅分析 rps=0.3415，告知用户 0.4519 缺失 |

---

## 🎯 技术决策

- **ideal_rps 取 0.40 而非 0.43**：E2E P90 在 0.43 档仅超标 1.1%，属临界，但 benchmark 框架保守取最后 PASS 档
- **不补测 0.41~0.42**：0.40 与 0.43 之间的精确边界对生产决策意义有限，0.40 已足够保守且可靠

---

## ⚠️ 未完成事项（guoxue Eagle3）

- [ ] Phase 3 四点网格验证（`IDEAL_RPS=0.40, PRODUCTION_RPS=0.23`）
- [ ] 生成最终 EVAL_REPORT.md
- [ ] Grafana 截图补充到各 REPORT.md

---

## 📈 下次会话启动检查清单（guoxue Eagle3）

```bash
# 确认 ideal_rps=0.40 后，启动 Phase 3
IDEAL_RPS=0.40 PRODUCTION_RPS=0.23 \
  bash scripts/benchmark/run_phase3_grid_guoxue_eagle3_4h20.sh

# Phase 3 完成后运行分析
# 运行 qps-peak-finder-analysis Skill 生成 REPORT.md
```

**关键参数备忘（guoxue Eagle3）**：

| 参数 | 值 | 来源 |
|------|----|----|
| avg_output_len | ~2204 tokens | rps=0.5878 infra-opti 测试 |
| ideal_rps | **0.40 req/s（24 RPM）** | 本次会话确认 |
| 边界区间 | 0.40 < ideal_rps < 0.43 | 本次会话确认 |
| PRODUCTION_RPS | 0.23 req/s（≈14 RPM）| 取 ideal_rps × 57% 安全系数 |
| SLA | TTFS P90 ≤1.5s，E2E P90 ≤180s | 历次测试沿用 |

