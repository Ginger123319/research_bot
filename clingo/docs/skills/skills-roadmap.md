# Skill 建设路线图

> 本工程专属 Skill 候选清单与优先级规划  
> 更新：2026-03-13

---

## 存储架构

```
clingo/docs/skills/          ← 真实存储（项目文档）
  traffic-dataset-prep/
    SKILL.md
  llm-deployment-docker/     ← 待建
  qps-benchmark-sweep/       ← 待建
  ...

.cursor/skills/              ← Cursor IDE 加载目录（软链接指向上方）
  traffic-dataset-prep  →  ../../clingo/docs/skills/traffic-dataset-prep
  brainstorming/             ← 通用 Skill（非本项目，保持原样）
  writing-skills/            ← 通用 Skill（非本项目，保持原样）
```

新增 Skill 流程：在 `clingo/docs/skills/<skill-name>/` 下创建，然后在 `.cursor/skills/` 下建软链接。

---

## 当前状态

| Skill | 优先级 | 状态 | 路径 |
|-------|--------|------|------|
| `traffic-dataset-prep` | P0 | ✅ 已验证 | `clingo/docs/skills/traffic-dataset-prep/` |
| `qps-benchmark-sweep` | P0 | ✅ 已验证 | `clingo/docs/skills/qps-benchmark-sweep/` |
| `qps-sweep-comparison` | P0 | ✅ 完成 | `clingo/docs/skills/qps-sweep-comparison/` |
| `llm-replay-benchmark` | P0 | ✅ 已验证 | `clingo/docs/skills/llm-replay-benchmark/` |
| `llm-deployment-docker` | P0 | ✅ 已验证 | `clingo/docs/skills/llm-deployment-docker/` |
| `llm-service-probing` | P1 | ✅ 已验证 | `clingo/docs/skills/llm-service-probing/` |
| `benchmark-result-analysis` | P2 | ✅ 完成 | offline_analysis.py（HTML + PNG + REPORT 骨架）|
| `model-evaluation-workflow` | P2 | ✅ 完成 | `clingo/docs/skills/model-evaluation-workflow/` |

---

## Skill 详情

### ✅ `traffic-dataset-prep`（P0，已完成）

**类型**：Technique  
**触发条件**：有线上 JSONL 业务日志，需要构建 benchmark 压测数据集  
**覆盖内容**：

| 步骤 | 内容 |
|------|------|
| 步骤1 | JSONL → CSV（DataConverter，read_only_time=False）|
| 步骤2 | 峰值窗口采样（DataSampler._select_data）|
| 步骤3 | 时间戳拼接（消除 >5min 段间间隔）|
| 步骤4 | 泊松插值（DataInterpolator，source_file 用拼接后的 CSV）|
| 步骤5 | 脏数据过滤（content 为 list 的多模态行）|

**参考脚本**：`scripts/data/process_ziwei_full.py`、`scripts/data/process_henpan_tarot_full.py`

**验证状态**：✅ 已用两个模型（ziwei-32b、hepan-72b）实测，REFACTOR 后补充了：
- `model_list` 必须包含中文别名（否则丢失 ~70% 数据）
- `income_time` 来源字段（`messages[0].time` 或 `request_info.session_time`）
- 步骤6：README 输出说明文档规范

---

### ✅ `llm-deployment-docker`（P0，已验证）

**类型**：Technique + Reference  
**触发条件**：需要用 Docker 部署 sglang 推理服务（本机可跑时自动执行，显存不足时输出参考命令）  
**覆盖内容**：

| 步骤 | 内容 |
|------|------|
| 预检 | nvidia-smi 空闲显存 + config.json 估算 VRAM + GPU 拓扑判断 TP/DP |
| 路径A | docker run 命令生成 + 健康检查轮询（max 120s）+ smoke test + 调用 llm-service-probing |
| 路径B | 显存不足时输出推荐命令配置供人工执行 |
| 参数速查 | tp-size/dp-size/base-gpu-id/chat-template/mem-fraction-static 等 |
| 常见报错 | 权限 / 端口冲突 / OOM / registry 认证 / 健康检查超时 |

**参考脚本**：`scripts/deploy/start_*.sh`  
**验证状态**：✅ 已用 tianji-querysafety-4b-v2-3 实测（DP=4 PCIe，2026-03-13）

---

### ✅ `qps-benchmark-sweep`（P0，已验证）

**类型**：Technique  
**触发条件**：需要找到模型的 QPS 拐点或承载边界  
**覆盖内容**：

- 档位设计策略（边界区 0.02步 / 中间区 0.04步 / 低 QPS 0.05步）
- 每档时长设置（60min / 45min / 30min）
- `CONFIG_LIST` 参数格式（`qps,0,0,0`）
- `COOLDOWN_SECS` 设置（90s 冷却）
- 拐点判断指标阈值（成功率 <99% / TTFT P90 明显抬升）

**参考脚本**：`scripts/benchmark/run_ziwei_4tp_qps_benchmark.sh`

---

### ✅ `qps-sweep-comparison`（P0，已完成）

**类型**：Technique + Reference  
**触发条件**：多组 QPS 扫描已完成，需要对比可视化或评估是否满足 SLA 基准  
**覆盖内容**：

- `multi_exp_compare.py` 配置与执行（N 组 → 3 个对比 HTML）
- 交互式图表操作（下拉过滤 + 独立 legend 切换）
- 通用 SLA 基准：TTFS P90 ≤ 1500ms，E2E P90 ≤ 150s
- 模型特定基准（tianji P95 ≤ 400ms 等）
- 拐点识别方法与多组差异解读

**工具**：`third_party/.../analysis/analysis/multi_exp_compare.py`

---

### ✅ `llm-replay-benchmark`（P0，已验证）

**类型**：Technique  
**触发条件**：需要验证已部署 LLM 服务能否在预期峰值负载下稳定运行（成功率 / 延迟符合 SLA）  
**覆盖内容**：

- 按数据集 `income_time` 时间戳回放（`--keep-income-time`），还原真实突发+低谷流量形态
- 与 QPS 扫描的区别（速率由数据控制 vs 固定 QPS；验证目标 vs 找承载上限）
- 数据文件选择原则（`_peak30min.csv` 直接回放 / `_poisson_{RPM}_stitched.csv` 放大回放）
- `--no-kvcache` + UUID 前缀防缓存命中
- `max_completion_tokens` 按输出类型设置（对话 4096 / 短输出 256）
- 实验命名约定与输出目录结构
- 成功判断标准（成功率 ≥ 99%，TTFT P90 无明显抬升，POST 异常 = 0）

**参考实验**：
- `logs/ziwei_peak_replay_20260310_163524`（poisson_100，3036 条，~60 min）
- `logs/tianji_querysafety_peak_replay_20260312_175115`（peak30min，44,099 条，~30 min，成功率 100%）

**验证状态**：✅ 已用两个模型（ziwei-32b、tianji-querysafety-4b）实测，均通过。其中 tianji-querysafety 使用 `_peak30min.csv` 直接回放（无泊松插值），验证了 Skill 对 CSV 源数据场景（情况 B）的兼容性。

---

### ✅ `llm-service-probing`（P1，已验证）

**类型**：Technique  
**触发条件**：对已部署服务进行能力探测，无业务数据时自动判断模型类型和使用场景  
**覆盖内容**：

| 步骤 | 内容 |
|------|------|
| 侦察 | P1 自我介绍 / P2 分类探测 / P3 安全探测，3条固定探针 |
| 判型 | 安全拦截模型 / 分类路由模型 / 通用对话模型，基于响应时间+输出格式 |
| 深探 | 按类型追加 2~5 条针对性探针，验证核心行为 |
| 报告 | 模型类型 + 使用场景描述 + 注意事项 |

**与 llm-deployment-docker 的关系**：deployment Skill 在 smoke test 通过后自动调用本 Skill  
**验证状态**：✅ 已用 tianji-querysafety-4b-v2-3 实测（安全拦截判型验证，REFACTOR 完毕，2026-03-13）

---

### ✅ `benchmark-result-analysis`（P2，完成）

**类型**：Technique + Reference  
**触发条件**：benchmark 执行完成，需要分析结果并出报告  
**计划内容**：

- llm-benchmark analysis 工具调用方式
- 从 HTML 报告中导出结构化数据（规划中）
- 量化报告章节模板
- 性能曲线解读（线性区 / 膝点 / 过载区）

---

### ✅ `model-evaluation-workflow`（P2，完成）

**类型**：Pattern（流程编排）  
**触发条件**：接入全新模型，需要从头到尾完成完整评估  
**覆盖内容**：

| 步骤 | 内容 |
|------|------|
| Step 0 | 信息收集（部署规格形态A/B + GPU 状态 + 业务数据 + 推理参数）|
| Step 1 | 本地 Docker 部署 → 委托 llm-deployment-docker Skill |
| Step 2 | 服务探测 → 委托 llm-service-probing Skill（无数据时）|
| Step 3 | 数据处理 → 委托 traffic-dataset-prep Skill（有数据时）|
| 🔴 断点 | 等待用户提供 k8s endpoint URL |
| Step 4 | 远端连通性验证（3项：/health + /models + smoke test）|
| Step 5 | Benchmark → 委托 llm-replay-benchmark + qps-benchmark-sweep |
| Step 6 | 结果分析 → 委托 benchmark-result-analysis + qps-sweep-comparison |

**关键设计**：
- 每步有跳过条件（检查产物是否已存在），支持跨会话续跑
- 人工断点：阶段一完成后 AI 主动暂停等待 URL
- progress.md 标准写入格式

**完成日期**：2026-03-13

---

## 建设时间线

```
✅ 完成:  traffic-dataset-prep（ziwei-32b / hepan-72b 两模型验证，REFACTOR 完毕）
✅ 完成:  qps-benchmark-sweep（ziwei/tianji 实测验证）
✅ 完成:  qps-sweep-comparison（多组 QPS 结果对比可视化 + SLA 评估，multi_exp_compare.py）
✅ 完成:  benchmark-result-analysis（offline_analysis.py + PNG 导出 + REPORT 骨架）
✅ 完成:  llm-replay-benchmark（ziwei-32b poisson_100 + tianji-querysafety-4b peak30min 两模型验证，2026-03-12）
✅ 完成:  llm-deployment-docker（tianji-querysafety-4b-v2-3 实测验证，DP=4 PCIe，2026-03-13）
✅ 完成:  llm-service-probing（tianji-querysafety-4b-v2-3 安全拦截判型验证，REFACTOR 完毕，2026-03-13）
✅ 完成:  model-evaluation-workflow（8步 Pattern，两阶段+人工断点，2026-03-13）
```

---

## 每个 Skill 的交付标准

按 `writing-skills` TDD 要求：

1. **RED**：无 Skill 时跑压力场景，记录默认行为
2. **GREEN**：写 SKILL.md，验证行为改善
3. **REFACTOR**：补充漏洞直到稳定

Skill 真实存储：`clingo/docs/skills/<skill-name>/SKILL.md`  
Cursor 加载软链：`.cursor/skills/<skill-name>` → `../../clingo/docs/skills/<skill-name>`
