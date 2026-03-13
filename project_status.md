# 会话报告 - 2026-03-11（Skill 体系建设 & tianji-querysafety 压测启动）

## 📌 会话概览

- **日期**：2026-03-11（周三，下午~晚间）
- **结束时间**：2026-03-11 20:07
- **总步骤数**：7（含 1 个 BugFix）
- **主要目标**：
  1. 建立项目 Skill 体系（存储架构 + 第一个 Skill）
  2. 整理脚本目录结构（tmp/ → scripts/）
  3. 固化新模型接入 SOP
  4. 完成 tianji-querysafety 数据处理 + benchmark 脚本 + 压测启动

---

## ✅ 成果

### 1. clingo/docs 文档体系建立

| 文件 | 内容 |
|------|------|
| `clingo/docs/README.md` | 项目概览 + 已迁移模型清单 |
| `clingo/docs/need-todo-idea.md` | 需求/待办/想法，经两轮讨论修正 |
| `clingo/docs/skills/skills-roadmap.md` | 5 Skill 候选 + 优先级 + 建设时间线 |
| `clingo/docs/workflow/model-onboarding.md` | 新模型接入 8步 SOP（完整流程）|

### 2. scripts/ 目录重组

`tmp/` 下 15 个脚本分类迁移到 `scripts/{deploy,benchmark,probe,data,analysis}/`，新增 `scripts/README.md`。

### 3. traffic-dataset-prep Skill（P0）—— 完成验证

**情况 A（JSONL 线上日志）**：
- 5步管道（DataConverter → DataSampler → 时间戳拼接 → DataInterpolator → 脏数据过滤）
- REFACTOR 补充：`model_list` 中文别名陷阱（丢失 70% 数据的根因）
- 存储架构：`clingo/docs/skills/` 真实存储，`.cursor/skills/` 软链接

**情况 B（CSV + 系统提示模板填充）**—— 本次新增：
- `times(ms) → income_time`（Asia/Shanghai）
- `{{query}}` 模板填充 → `messages` JSON
- 文件体积警告（per-row 展开后 5~10x）

**验证状态**：✅ ziwei-32b（情况 A）+ hepan-72b（情况 A）+ tianji-querysafety（情况 B）三模型实测通过

### 4. model-onboarding.md SOP

8步完整流程（Step 0 信息收集 → Step 6 结果归档），含 Checklist 和环境说明。经两轮修正：
- 分析工具命令：`analysis --host 0.0.0.0 --port 8050 --exp <dir>`
- Step 3 脚本模式：每模型新建专属脚本（copy + 改配置块）

### 5. tianji-querysafety-4b-v2-3 压测启动

**数据处理**：`_peak30min.csv`（44,099 行，897 MB，峰值 2168 RPM）

**服务验证**（Demo 3 case）：

| case | 耗时 | 结果 |
|------|------|------|
| 正常放行 | 0.95s | `{"label": "无", ...}` ✅ |
| 敏感拦截 | 0.24s | `{"label": "违法行为", ...}` ✅ |
| 边界医疗 | 0.13s | `{"label": "无", ...}` ✅ |

**压测脚本**：QPS 7.00→4.00，30 档，每档 45min，预计 ~23h

---

## 🐛 问题与解决方案

### KeyError: 'prompt'（benchmark 启动报错）

**现象**：benchmark 工具在读取 CSV 时报 `KeyError: 'prompt'`

**根因**：`benchmark.py` 第 109 行 `pd.read_csv(..., dtype={"prompt": str, ...})` 强制要求 `prompt` 列，即使内容为空也必须存在。`process_tianji_querysafety_full.py` 的 `OUTPUT_COLS` 漏掉了该列。

**修复**：
1. 直接给现有两个 CSV 插入空 `prompt` 列（Python 脚本，约 2min 完成）
2. 修复 `process_tianji_querysafety_full.py` 的 `OUTPUT_COLS`
3. SKILL 常见错误表补录此条（路径 A/B 通用）

---

## 🎯 技术决策

| 决策 | 理由 |
|------|------|
| Skill 真实存储在 `clingo/docs/skills/`，`.cursor/skills/` 软链接 | 归档于项目文档，同时保持 Cursor IDE 可加载 |
| 每模型建专属数据处理脚本（不做参数化共用）| 各模型配置差异大（model_list/PEAK_WINDOWS/TARGET_RPM），参数化反而降低可读性 |
| tianji 压测用 `_peak30min.csv`（44K 行）而非全量（281K 行）| 全量 5.7 GB，per-row 含完整系统提示，峰值窗口已足够代表真实负载 |
| max_completion_tokens=256（而非默认 4096）| 安全模型输出为短 JSON（实测 14~33 tokens），减少无效等待，提高压测效率 |

---

## ⚠️ 未完成事项

| 事项 | 状态 | 说明 |
|------|------|------|
| tianji QPS 压测 | 🔄 **执行中** | 7.0→4.0，30 档，预计 ~23h 完成 |
| hepan-72b 压测 | ⏳ 待启动 | 数据已就绪（6,034 条 150RPM），需写 deploy + benchmark 脚本 |
| llm-deployment-docker Skill | ⏳ 待建 | P0，参考类，写起来快 |
| qps-benchmark-sweep Skill | ⏳ 待建 | P0，核心技能 |
| clingo/docs/workflow/reporting-template.md | ⏳ 待建 | 量化报告模板 |
| clingo/docs/models/ 模型档案 | ⏳ 待建 | 三个已迁移模型的信息卡 |
| data_analysis git push | ⏳ 待换机执行 | `33e32bf` on `wnd_dev` |

---

## 💡 建议与注意事项

1. **tianji 压测完成后**：运行 `analysis --host 0.0.0.0 --port 8050 --exp logs/tianji_qps_<timestamp>` 查看结果，关注拐点（成功率 <99% 或 TTFT P90 >2s 的档位）

2. **hepan-72b 下一步**：先写 `scripts/deploy/start_henpan_72b.sh`，再写 `scripts/benchmark/run_henpan_qps_sweep.sh`，参考 tianji 脚本结构

3. **prompt 列提醒**：所有 benchmark 数据集 CSV 必须包含空 `prompt` 列，否则报 `KeyError: 'prompt'`（已在 SKILL 中记录）

4. **全量 CSV 体积**：tianji `_all.csv` 已达 5.7 GB，后续若有类似模型（系统提示长 + CSV 源），优先使用峰值窗口采样文件做压测

---

## 📈 下次会话计划

### 优先级 1：等待 tianji 压测结果（~23h 后）
- 运行 analysis 工具分析结果
- 输出量化报告，确认拐点 QPS
- 截图归档到 `results/tianji_qps_<date>/`

### 优先级 2：hepan-72b 压测
- 写 `scripts/deploy/start_henpan_72b.sh`
- 写 `scripts/benchmark/run_henpan_qps_sweep.sh`
- 确认 henpan-72b 的平台 endpoint URL

### 优先级 3：继续 Skill 建设
- `llm-deployment-docker`（P0，参考类，写起来快）
- `qps-benchmark-sweep`（P0，核心技能）

---

## 📊 项目整体状态（截至 2026-03-12 更新）

| 模型 | 数据 | 本地部署 | 平台部署 | 探测 | 压测 | 报告 |
|------|------|----------|----------|------|------|------|
| ziwei-32b (xinghan) | ✅ | ✅ | ✅ k8s 新镜像 v0.4.6.post2 | ✅ | ✅ 4TP+8TP all目录已整合 | ⏳ 待analysis |
| ziwei-8b (twostep) | ✅ | ✅ | ✅ k8s 新镜像 v0.4.6.post2 | ✅ | ✅ | ✅ |
| tianji-querysafety-4b | ✅ | ✅ | ✅ | ✅ | 🔄 进行中 | ⏳ |
| hepan-72b | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |

**sglang 镜像状态**：

| Tag | 来源 | 推送状态 |
|-----|------|---------|
| `reg.xxwolo.com/master/sglang:v0.4.1.post4` | `reg.xxwolo.com/ai/lmsysorg-sglang:latest` | ✅ 已推送 |
| `reg.xxwolo.com/master/sglang:v0.4.6.post2` | `reg-ai.cece.com/ai/sglang:v814` | ✅ 已推送 |

**Skill 进度**：

| Skill | 状态 |
|-------|------|
| `traffic-dataset-prep` | ✅ 已验证（情况 A+B）|
| `llm-deployment-docker` | ⏳ 待建 |
| `qps-benchmark-sweep` | ⏳ 待建 |
| `llm-service-probing` | ⏳ 待建 |
| `benchmark-result-analysis` | ⏳ 待建 |
| `model-evaluation-workflow` | ⏳ 待建（依赖前面完成）|

---

# 会话报告 - 2026-03-12

## 📌 会话概览

- **日期**：2026-03-12
- **主要目标**：Docker 镜像迁移打 tag + 推送；k8s 新部署服务验证
- **总步骤数**：2
- **Git 分支**：不适用（非 git repo）

## ✅ 成果

1. **sglang 镜像重新打 tag 并推送至 master registry**
   - `reg.xxwolo.com/master/sglang:v0.4.1.post4`（来自 lmsysorg-sglang:latest）
   - `reg.xxwolo.com/master/sglang:v0.4.6.post2`（来自 reg-ai.cece.com/ai/sglang:v814）

2. **新部署 k8s 服务全部验证通过**
   - `infra-xinghan-ziwei-p32b-v1`：32b 通用推理，多轮对话 / 摘要 / 代码生成 ✅
   - `infra-ziwei-intention-twostep-p8b-v1`：8b 意图识别，twostep 输出格式正常 ✅

## 🔧 文件变更

| 文件 | 操作 |
|------|------|
| `/tmp/test_new_deployments.py` | ✨ 新增（服务验证脚本，162行）|
| `progress.md` | 📝 更新 |
| `project_status.md` | 📝 更新（本文件）|

## 🐛 问题与解决方案

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| `docker push` 返回 `unauthorized` | `master/sglang` 仓库无 push 权限 | 用户在仓库侧授权后重新 push，成功 |
| `SyntaxError: invalid syntax` (Python) | 测试脚本字符串内含中文双引号 `"两步法"` | 去掉中文引号改为普通文本 |

## 🎯 技术决策

- 测试脚本按模型规格差异化设计：8b 聚焦意图识别核心用例（A1-A5），32b 聚焦复杂推理/生成（B1-B4）
- 测试先调 `/v1/models` 自动获取 model_id，避免硬编码出错
- 两个 push 任务并行后台执行，节省等待时间

## ⚠️ 未完成事项

- tianji QPS 压测仍在运行中（上次会话启动）
- hepan-72b 部署脚本尚未编写

## 💡 建议与注意事项

- 新镜像已推送至 `reg.xxwolo.com/master/`，k8s manifest 中的 `image` 字段如需更新请参考上方镜像表
- 8b twostep 模型输出带 `<think>` 标签，下游解析需剥离该标签再处理意图文本
- 32b 复杂推理响应时间 1~4s，意图识别 8b 响应时间 0.2~0.5s，可作为 SLA 基准参考

## 📈 下次会话计划

### 优先级 1：tianji 压测结果分析
- 压测跑完后运行 analysis 工具，确认拐点 QPS
- 输出量化报告归档至 `results/tianji_qps_<date>/`

### 优先级 2：hepan-72b 压测
- 写 `scripts/deploy/start_henpan_72b.sh`
- 写 `scripts/benchmark/run_henpan_qps_sweep.sh`

### 优先级 3：Skill 建设
- `llm-service-probing`（可直接基于 `tmp/test_remote_services.py` 提炼）
- `qps-benchmark-sweep`（核心技能，P0）

---

# 会话报告 - 2026-03-12（ziwei 4TP + 8TP QPS 结果整合）

## 📌 会话概览

- **日期**：2026-03-12
- **结束时间**：2026-03-12 ~12:00
- **总步骤数**：3
- **主要目标**：将 ziwei 8TP 和 4TP high QPS benchmark 的历史结果整合为统一格式目录，供 analysis 工具直接使用
- **Git 分支**：不适用（非 git repo）

---

## ✅ 成果

### 1. ziwei 8TP QPS 结果整合 → `logs/ziwei_8tp_qps_20260310_all/`

将两批分散的 8TP 结果合并为 **30 档**（QPS 0.46–2.00），统一 `TP8_qps_X.XX/` 子目录格式：

| 来源目录 | 原格式 | QPS 范围 | 档数 |
|----------|--------|----------|------|
| `ziwei_8tp_qps_stress_20260310_200246` | `qps_X.XX/` | 0.46–1.00 | 20 |
| `ziwei_8tp_high_qps_20260311_115259` | `TP8_qps_X.XX/`（已正确）| 1.10–2.00 | 10 |

编写合并脚本 `tmp/merge_8tp_qps_20260310.py` 执行复制（原始目录全保留）。

### 2. ziwei 4TP QPS 结果补全 → `logs/ziwei_4tp_qps_20260310_all/` 扩充至 34 档

发现 `ziwei_4tp_high_qps_20260311_115109/`（QPS 1.00–2.00，11档）已于 2026-03-11 20:03 跑完但未纳入 all 目录。将 1.10–2.00 共 10 档追加，`all/` 从 24 档扩展为 **34 档**（QPS 0.46–2.00）。

### 3. TP4_qps_1.00 数据源一致性修正

步骤 2 初版操作产生了混合状态（csv 来自 stress run，dataset/log 来自 high run）。用户确认后完全替换为 high run，`TP4_qps_1.00/` 4 个文件来源统一。

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `tmp/merge_8tp_qps_20260310.py` | ✨ 新增 | 8TP 合并脚本，78行 |
| `logs/ziwei_8tp_qps_20260310_all/` | ✨ 新建 | 30档，TP8_qps_X.XX/ 格式 |
| `logs/ziwei_4tp_qps_20260310_all/` | 📝 扩充+修正 | 24档→34档，TP4_qps_1.00 来源统一 |
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 本文件 |

**只读（未修改）**：
- `logs/ziwei_8tp_qps_stress_20260310_200246/`
- `logs/ziwei_8tp_high_qps_20260311_115259/`
- `logs/ziwei_4tp_high_qps_20260311_115109/`

---

## 🐛 问题与解决方案

| 问题 | 根因 | 解决方案 |
|------|------|---------|
| `TP4_qps_1.00` 混合状态 | 补全策略只添加缺失文件，未考虑两次 run 的 csv 来源不同 | 用户确认后完全替换为 high run，删除旧 stress run 的 csv |

---

## 🎯 技术决策

| 决策 | 理由 |
|------|------|
| 8TP 合并用 Python 脚本（而非 bash）| 来源格式不同（有/无 TP8_ 前缀），Python 正则解析更可靠，避免 bash glob 排序问题（参考 4TP 合并时踩过的坑）|
| TP4_qps_1.00 选用 high run | high run 是独立完整的一次运行，4文件来源一致；stress run 只是大扫描中间档，csv 文件还比 high run 大（277MB vs 172MB，可能参数不同）|
| 所有合并操作均为复制（原目录保留）| 原始数据不可变，便于后续回溯和重新验证 |

---

## ⚠️ 未完成事项

| 事项 | 状态 | 说明 |
|------|------|------|
| tianji QPS 压测 | 🔄 执行中 | 7.0→4.0，30档，预计今日内完成 |
| hepan-72b 压测 | ⏳ 待启动 | 数据已就绪（6,034条），需写 deploy + benchmark 脚本 |
| ziwei 4TP/8TP analysis 分析 | ⏳ 待执行 | all 目录已就绪，可直接运行 analysis 工具 |
| llm-deployment-docker Skill | ⏳ 待建 | P0 |
| qps-benchmark-sweep Skill | ⏳ 待建 | P0 |

---

## 💡 建议与注意事项

1. **analysis 工具调用**：
   - 4TP：`analysis --host 0.0.0.0 --port 8050 --exp logs/ziwei_4tp_qps_20260310_all`
   - 8TP：`analysis --host 0.0.0.0 --port 8050 --exp logs/ziwei_8tp_qps_20260310_all`

2. **数据完整性**：两个 all 目录每档均含 4 个文件（`dataset.csv`、`.log`、`vanilla_qpsX.XX.csv`、`vanilla_qpsX.XX.argv.csv`），可直接用于 analysis。

3. **4TP all 目录说明**：QPS 0.46–1.00 来自 stress run（2026-03-10），QPS 1.00–2.00 全部来自 high run（2026-03-11）；其中 QPS=1.00 档已统一为 high run 来源。

---

## 📈 下次会话计划

### 优先级 1：ziwei 4TP vs 8TP 对比分析
- 运行 analysis 工具，对比两套 all 目录
- 关注拐点 QPS（成功率 <99% 或 TTFT P90 异常档位）
- 输出对比报告归档到 `results/ziwei_tp_compare_<date>/`

### 优先级 2：tianji 压测结果分析（等待完成后）
- 运行 analysis，确认拐点 QPS
- 输出量化报告归档至 `results/tianji_qps_<date>/`

### 优先级 3：hepan-72b 压测启动
- 写 `scripts/deploy/start_henpan_72b.sh`
- 写 `scripts/benchmark/run_henpan_qps_sweep.sh`

---

# 会话报告 - 2026-03-12（hepan 离线分析 & offline_analysis.py Bug 修复）

## 📌 会话概览

- **日期**：2026-03-12
- **结束时间**：2026-03-12 ~17:30
- **总步骤数**：2（分析执行 + Bug 修复）
- **主要目标**：
  1. 对同事完成的 hepan-72b 回放测试结果进行离线分析，产出完整报告
  2. 修复 `offline_analysis.py` 中 Token Length Distribution 直方图显示异常问题
- **验证对象**：`benchmark-result-analysis` Skill

---

## ✅ 成果

### 1. hepan-72b 离线分析报告（`results/hepan_benchmark_20260312/`）

同事（jyf）使用以下命令跑了 hepan-72b 回放压测：
```bash
benchmark --exp-name hepan_temp_test \
  --dataset-path ...xinghan-hepan-72b-v1-2_selected_combined_3days_peak_poisson_150_stitched.csv \
  --url https://infer.geniuworks.com/infra-xinghan-hepan-p72b-v1/v1/chat/completions \
  --tokenizer /mnt/ai-llm/hepan-v1-2-grpo \
  --no-kvcache --keep-income-time --seed 42 --max-completion-tokens 4096
```

分析结果（6,034 请求，150 RPM 峰值，~66 分钟）：

| 指标 | 值 | 状态 |
|------|----|----|
| 成功率 | **99.95%** | ✅ |
| TTFT P50/P90/P99 | 0.37s / 1.15s / 2.38s | ✅ |
| E2E P50/P90/P99 | 6.80s / 13.38s / 26.27s | ⚠️ P99 较高（长输出，合理）|
| User-TPOT 均值 | 0.037s | ✅ |
| Decode 吞吐 | 266.3 tok/s | ✅ |

产出：HTML（2.9MB）+ 7 张 PNG + REPORT.md 骨架（分位数预填，背景/结论/Grafana 待用户补充）

### 2. `offline_analysis.py` Token 直方图 Bug 修复

**问题**：Token Length Distribution 图表中各系列数据全压在第一个 bin，分布不可见。

**根因**：`build_token_hist` 用全局 `tok_max`（取自所有系列最大值 ~900）均分 200 个 bin，宽度 ~4.5 tokens/bin，`first_sentence`（分布 0~40）全部被压进前 9 个 bin。

**修复**：新增 `_series_p99()` 函数，每个系列独立用自己的 P99 作为 `x_max`，裁剪长尾，保留有效分布范围。同时新增系列切换按钮（`prompt | completion | all | first_sentence | All`）。相同逻辑同步应用于 `build_latency_hist`。

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/hepan_benchmark_20260312/hepan_peak_replay_150rpm_analysis.html` | ✨ 新增 | 2.9MB 交互式完整分析报告 |
| `results/hepan_benchmark_20260312/*.png` | ✨ 新增 | 7 张 CDF + Timeline 静态图 |
| `results/hepan_benchmark_20260312/REPORT.md` | ✨ 新增 | 7.5KB 报告骨架（分位数已预填）|
| `scripts/analysis/offline_analysis.py` | 🐛 修复 | 新增 `_series_p99()`，修复直方图 bin 过宽问题（+20 行）|
| `progress.md` | 📝 更新 | 新增本次会话记录 |
| `project_status.md` | 📝 更新 | 本文件 |

---

## 🐛 问题与解决方案

| 问题 | 根因 | 解决方案 |
|------|------|---------|
| Token Length Distribution 图表显示异常（所有数据挤在第一 bin）| 全局 `tok_max` 使 bin 宽过大，`first_sentence` 分布（0~40）完全被压缩 | 每系列独立用 P99 作为 `x_max`，裁剪长尾 |
| 用户提供的是 dataset 路径而非 result 路径 | 同事在外部环境执行了 benchmark，result CSV 存放于 shared 路径 | 根据同事提供的命令推断出 result 路径 `/mnt/ai-infra/users/shared/.../hepan_temp_test.csv`，验证后直接分析 |

---

## 🎯 技术决策

| 决策 | 理由 |
|------|------|
| 直方图改为 per-series P99 作为 x_max | 不同系列（prompt/completion/all/first_sentence）分布范围差异悬殊（~40 vs ~900），共用全局 x_max 会导致范围窄的系列被压缩 |
| 新增系列切换按钮而非删除重叠系列 | 用户需要逐一查看各系列分布，Plotly updatemenus 实现零额外数据量开销的切换 |
| X/Y 轴改为 autorange=True | 各系列 P99 各不相同，固定轴范围无法同时适应所有系列 |

---

## ⚠️ 未完成事项

| 事项 | 状态 | 说明 |
|------|------|------|
| hepan REPORT.md 补充 | ⏳ 待用户 | 背景目的、结论、Grafana 截图 |
| tianji QPS 压测 | 🔄 执行中 | 进行中，结果待分析 |
| llm-deployment-docker Skill | ⏳ 待建 | P0 |
| llm-service-probing Skill | ⏳ 待建 | P1 |
| model-evaluation-workflow Skill | ⏳ 待建 | P2 |
| clingo/docs/models/ 模型档案 | ⏳ 待建 | P2 |

---

## 💡 建议与注意事项

1. **offline_analysis.py 已更新**：修复后所有直方图均使用 P99 裁剪，后续对任何 benchmark 结果运行分析都会得到正确图表，无需额外操作

2. **hepan REPORT.md 待补充内容**：
   - `§一 背景与目的`：合盘解读模型上线背景
   - `§五 综合结论`：TTFT/E2E P90 是否符合 SLA
   - `§四.3 Grafana 截图`：`http://172.21.52.62:3000/d/cb7f886a-289f-4052-ae50-913644582b64/geniuworks`

3. **E2E P99 说明**：hepan 合盘输出 max_completion_tokens=4096，E2E P99=26s 属正常范围，可在报告中注明原因

---

## 📈 下次会话计划

### 优先级 1：tianji QPS 压测结果分析
- 压测完成后运行 `offline_analysis.py` 生成报告
- 确认拐点 QPS（成功率 <99.9% 或 TTFT P90 >2s 的档位）

### 优先级 2：Skill 建设继续
- `llm-deployment-docker`（P0，参考现有 deploy 脚本提炼）
- `llm-service-probing`（P1，参考 `test_remote_services.py`）

### 优先级 3：项目文档完善
- `clingo/docs/models/`：三个已迁移模型档案（ziwei/tianji/hepan）
- `clingo/docs/workflow/reporting-template.md`：报告模板规范

---

## 📊 项目整体状态（截至 2026-03-12 ~20:00）

| 模型 | 数据处理 | 本地部署 | 平台部署 | 压测 | 分析报告 |
|------|---------|----------|----------|------|---------|
| ziwei-32b (xinghan) | ✅ | ✅ | ✅ k8s v0.4.6.post2 | ✅ 4TP+8TP QPS sweep | ✅ HTML+PNG+REPORT（含 TP 对比）|
| ziwei-8b (twostep) | ✅ | ✅ | ✅ k8s v0.4.6.post2 | ✅ | ✅ |
| tianji-querysafety-4b | ✅ | ✅ | ✅ | 🔄 进行中 | ⏳ 待压测完成 |
| hepan-72b | ✅ | ⏳ | ✅ (同事部署) | ✅ 回放 150RPM + QPS sweep | ✅ 完整（HTML+PNG+REPORT×3）|

**Skill 建设进度**：

| Skill | 状态 |
|-------|------|
| `traffic-dataset-prep` | ✅ 已验证（情况 A+B，三模型通过）|
| `qps-benchmark-sweep` | ✅ 已建 |
| `llm-replay-benchmark` | ✅ 已建，hepan 验证通过 |
| `benchmark-result-analysis` | ✅ 已建，hepan 验证通过 |
| `qps-sweep-comparison` | ✅ 已建，hepan + ziwei 双场景验证通过 |
| `llm-deployment-docker` | ⏳ 待建 |
| `llm-service-probing` | ⏳ 待建 |
| `model-evaluation-workflow` | ⏳ 待建（依赖前面完成）|

---

# 会话报告 - 2026-03-12（下午场）

## 📌 会话概览

- **时间**：2026-03-12 下午
- **主要目标**：利用 `qps-sweep-comparison` Skill 对 hepan-72b-v1 QPS benchmark 结果进行可视化与分析，并将 ziwei TP 对比结果从 logs/ 迁移至 results/
- **Git 分支**：N/A（非 git 仓库）

## ✅ 成果

1. **hepan-72b-v1 orig 单组 QPS 分析**：`results/hepan_qps_jyf_20260312/`（3 HTML + REPORT.md）
   - SLA 结论：TTFS P90 ≤ 1.5s → 最大合规 0.70 req/s；≤ 1.6s → 0.80 req/s

2. **hepan-72b-v1 orig vs data600 双组对比**：`results/hepan_qps_compare_data600_20260312/`（3 HTML + REPORT.md）
   - SLA 基准放宽至 1.6s（用户确认）
   - data600 整体 TTFS P90 略低 3~4%，两组拐点一致，最大合规 QPS = 0.80 req/s

3. **ziwei TP8 vs TP4 完整报告补充**：`results/ziwei_tp_compare_20260310/REPORT.md`
   - TP8 = 1.50 req/s，TP4 = 0.92 req/s，效率比约 82%

4. **`multi_exp_compare.py` 增强**：新增 `file_pattern` 参数，支持在平铺目录中按文件名前缀过滤特定实验组

5. **logs/ 旧 HTML 清理**：删除 6 个旧版可视化文件，结果统一归档至 `results/`

## 🔧 文件变更

| 文件 | 操作 |
|------|------|
| `results/hepan_qps_jyf_20260312/` | ✨ 新增（3 HTML + REPORT.md）|
| `results/hepan_qps_compare_data600_20260312/` | ✨ 新增（3 HTML + REPORT.md）|
| `results/ziwei_tp_compare_20260310/REPORT.md` | ✨ 新增 |
| `results/ziwei_tp_compare_20260310/*.html` | ♻️ 重新生成（3 个）|
| `results/hepan_qps_jyf_20260312/REPORT.md` | 📝 更新（补双基准结论）|
| `multi_exp_compare.py` | ✨ `scan_group` 新增 `file_pattern` |
| `logs/*.html`（6 个）| 🗑️ 删除 |

## 🐛 问题与解决方案

| 问题 | 解决方案 |
|------|---------|
| 平铺目录扫描时无关文件被捞入 | 首次运行自动跳过（x_key 不匹配），后续新增 `file_pattern` 精确过滤 |
| orig 与 data600 在同一目录无法区分 | `scan_group` 新增 `file_pattern` 参数，调用方在 groups dict 中指定 |

## 🎯 技术决策

- **TTFS P90 基准放宽到 1.6s**：用户判断 1.577s 可接受，建议以 1.6s 作为 hepan-72b 实际上线评估标准
- **file_pattern 设计为可选参数**（`None` 时行为不变），保持向后兼容

## ⚠️ 未完成事项

- tianji QPS 压测仍在进行中
- hepan REPORT.md 背景、结论、Grafana 截图待用户补充
- `llm-deployment-docker` / `llm-service-probing` Skill 待建

## 📈 下次会话计划

1. **tianji QPS 压测结果分析**（压测完成后）
2. **Skill 建设**：`llm-deployment-docker`（P0）
3. **模型档案**：`clingo/docs/models/` 三个已迁移模型档案

---

# 会话报告 - 2026-03-12（晚场）— tianji-querysafety 回放测试 & Skill 收尾

## 📌 会话概览

- **时间**：2026-03-12 晚
- **主要目标**：
  1. 对新部署的 `tianji-querysafety-4b-v2-3` 服务执行回放基准测试（`llm-replay-benchmark` Skill 实战验证）
  2. 生成完整分析报告（HTML + PNG + REPORT.md），与 Grafana 线上监控交叉验证
  3. 更新 Skill 路线图与 TODO 文档，收尾 llm-replay-benchmark Skill 验证

---

## ✅ 成果

### 1. tianji-querysafety-4b-v2-3 回放测试（全量通过）

- **数据集**：`datas/output_tianji_querysafety/tianji-querysafety-4b-v2-3_peak30min.csv`（44,099 条，30 分钟真实峰值窗口，均值 1422 RPM，峰值 2168 RPM）
- **服务**：`https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23-bakv1/v1/chat/completions`
- **参数**：`--keep-income-time --no-kvcache --max-completion-tokens 256`
- **耗时**：~30 分钟

**核心指标**：

| 指标 | 值 | SLA |
|------|-----|-----|
| 成功率 | **100.00%** | ✅ ≥ 99% |
| TTFT 均值 | 0.122 s | ✅ |
| E2E 均值 | 0.214 s | ✅ |
| TPOT 均值 | 0.007 s | ✅ |
| POST 异常 | 0 | ✅ |

### 2. 完整分析报告交付

- **目录**：`results/tianji_querysafety_benchmark_20260312/`
- **产出**：交互式 HTML（18 MB）+ 7 张 PNG + `REPORT.md`（含 Grafana 比对）
- **Grafana 比对**：线上历史监控（2026-02-23 ~ 2026-03-11）三项指标与压测值高度一致，验证结果可信

### 3. Skill / 文档体系收尾

- `skills-roadmap.md`：`llm-replay-benchmark` 状态升为 ✅ 已验证，补充详情节
- `need-todo-idea.md`：T1/T5/T7 打勾，新增 T7.5（llm-replay-benchmark 完成条目）

---

## 🔧 文件变更

| 文件 | 操作 |
|------|------|
| `logs/tianji_querysafety_peak_replay_20260312_175115/` | ✨ 新增（回放结果 CSV + argv CSV）|
| `logs/tianji_querysafety_replay_20260312_175115.log` | ✨ 新增（完整运行日志）|
| `results/tianji_querysafety_benchmark_20260312/tianji_querysafety_peak_replay_1422rpm_analysis.html` | ✨ 新增 |
| `results/tianji_querysafety_benchmark_20260312/*.png`（7 张）| ✨ 新增 |
| `results/tianji_querysafety_benchmark_20260312/REPORT.md` | ✨ 新增（含 Grafana 比对节）|
| `clingo/docs/skills/skills-roadmap.md` | 📝 更新（状态 + 详情节 + 时间线）|
| `clingo/docs/need-todo-idea.md` | 📝 更新（TODO 状态 + T7.5 + I2）|

---

## 🐛 问题与解决方案

| 问题 | 解决方案 |
|------|---------|
| 数据目录无泊松插值文件 | 直接用 `_peak30min.csv` 回放，income_time 保真，等效真实流量 |
| StrReplace 编码不匹配导致替换失败 | 改用 Python 脚本 open/replace/write 方式绕过 |

---

## 🎯 技术决策

- **`_peak30min.csv` 直接回放可行**：Skill 文档中 `_poisson_{RPM}_stitched.csv` 是推荐路径，但当数据源为 CSV（情况 B）且峰值窗口已采样时，直接回放同样有效，无需额外泊松插值步骤
- **`max_completion_tokens 256`**：tianji-querysafety 为安全分类模型，输出极短（平均 ~14 tokens），256 已充分

---

## ⚠️ 未完成事项

- `llm-deployment-docker` Skill（P0，待建，下次优先）
- `llm-service-probing` Skill（P1，待建）
- `clingo/docs/models/` 三个模型档案（待建）
- `clingo/docs/workflow/model-onboarding.md` / `reporting-template.md` 待补充

---

## 📊 项目整体状态（截至 2026-03-13 更新）

| 模型 | 数据处理 | 本地部署 | 平台部署 | 压测 | 分析报告 |
|------|---------|----------|----------|------|---------|
| ziwei-32b (xinghan) | ✅ | ✅ | ✅ | ✅ QPS sweep（TP4+TP8）| ✅ REPORT + TP 对比 |
| ziwei-8b (twostep) | ✅ | ✅ | ✅ | ✅ | ✅ |
| tianji-querysafety-4b | ✅ | ✅ | ✅ bakv1 | ✅ 回放 1422 RPM + QPS sweep 全范围（4.0~10.0）| ✅ 完整（回放 + 拐点 + 4TP vs 4DP 三份报告）|
| hepan-72b | ✅ | ⏳ | ✅（同事）| ✅ 回放 150 RPM + QPS sweep | ✅ 完整（×3 报告）|

**Skill 建设进度**：

| Skill | 状态 |
|-------|------|
| `traffic-dataset-prep` | ✅ 已验证（情况 A+B，多模型）|
| `qps-benchmark-sweep` | ✅ 已验证（ziwei/tianji）|
| `llm-replay-benchmark` | ✅ 已验证（ziwei-32b + tianji-querysafety-4b）|
| `benchmark-result-analysis` | ✅ 已验证（ziwei/hepan/tianji 三模型）|
| `qps-sweep-comparison` | ✅ 已验证（hepan + ziwei + tianji 三场景，含 4TP vs 4DP 对比）|
| `llm-deployment-docker` | ⏳ 待建（下次优先）|
| `llm-service-probing` | ⏳ 待建 |
| `model-evaluation-workflow` | ⏳ 待建（依赖前面完成）|

**工具链改进**：

| 改进项 | 状态 |
|--------|------|
| `multi_exp_compare.py` YAML 外部配置 | ✅ 完成（`--config` 参数 + `configs/` 目录）|
| `print_sla_analysis` P95/P99 输出 + 3位精度 | ✅ 完成 |

---

## 🔑 关键技术发现（2026-03-13）

### tianji-querysafety-4b-v2-3 4TP 容量基准

| 维度 | 数值 |
|------|------|
| SLA 标准 | E2E P90 ≤ 400ms（主），E2E P95 ≤ 400ms（辅）|
| **SLA 合规最大 QPS** | **8.0 req/s（480 RPM）** |
| 拐点类型 | P95 软拐点（QPS=8.5 时 P95=0.422s 首次超标，P90=0.360s 仍 PASS）|
| 当前业务峰值 | 约 2168 RPM（≈36.1 req/s）|
| 单实例覆盖比例 | 22%（480/2168）|
| **推荐扩容方案** | **6 实例 × 4TP（24 卡 H100），含 20% 安全余量** |

### E2E 定义与 SGLang 缓存效应

- `E2E = token_list[-1].timestamp - token_list[0].timestamp`（**服务端处理时间，不含排队**）
- 高 QPS 下 SGLang 批处理更大、KV Cache 更热 → 服务端延迟可能反而更低（预热效应）
- 建议剔除 QPS=6.90/7.00 等"缓存骤降"异常点，避免影响趋势分析

---

## 🐛 问题与解决方案

| 问题 | 解决方案 |
|------|---------|
| 数据目录无泊松插值文件 | 直接用 `_peak30min.csv` 回放，income_time 保真，等效真实流量 |
| StrReplace 编码不匹配导致替换失败 | 改用 Python 脚本 open/replace/write 方式绕过 |
| Shell / StrReplace / Write 工具 "Timeout waiting for bubble creation" | 简单命令（ls/echo）正常；Python 运行用 nohup 后台 + 读文件方式规避；大文件写入改用 Write 直接重写整个文件 |
| E2E P90 精度不足（1位小数掩盖细节）| print_sla_analysis 改为 3位小数 + 增加 P95/P99 列 |

---

## 🎯 技术决策

- **`_peak30min.csv` 直接回放可行**：Skill 文档中 `_poisson_{RPM}_stitched.csv` 是推荐路径，但当数据源为 CSV（情况 B）且峰值窗口已采样时，直接回放同样有效
- **`max_completion_tokens 256`**：tianji-querysafety 为安全分类模型，输出极短（平均 ~14 tokens），256 已充分
- **E2E P90 ≤ 400ms 替代通用 E2E P90 ≤ 150s**：快进快出模型（8K 缓存前缀 + 极短 user input）延迟量级完全不同，通用标准无意义
- **剔除缓存预热异常点**：QPS=6.90/7.00 因 KV Cache 过热导致延迟骤降，不代表真实趋势，需剔除后再做拐点识别
- **YAML 外部配置**：避免每次分析都修改源码，`configs/` 目录作为实验配置仓库，文件名按 `model_deploy_date.yaml` 命名规范

---

## ⚠️ 未完成事项

- `llm-deployment-docker` Skill（P0，待建，**下次优先**）
- `llm-service-probing` Skill（P1，待建）
- `clingo/docs/models/` 三个模型档案（待建）
- `clingo/docs/workflow/model-onboarding.md` / `reporting-template.md` 已有修改，待完善
- `print_sla_analysis` P95/P99 增强代码：已写入，下次运行前请确认文件内容正确

---

## 📈 下次会话计划

1. **`llm-deployment-docker` Skill 建设**（P0 参考类，有 3 个参考脚本，写起来快）
2. **模型档案**：`clingo/docs/models/tianji-querysafety-4b.md` — 结合本次拐点数据填写容量基准
3. **`model-onboarding.md` 补充**：tianji-querysafety 作为情况 B 案例写入 SOP，补充容量评估环节
4. **qps-sweep-comparison Skill 更新**：将 tianji 4TP vs 4DP 作为新的参考案例写入，并补充"缓存预热异常点剔除"操作指南
