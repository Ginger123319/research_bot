# 评估资产管理 & openclaw 接管设计

**日期**：2026-03-17  
**状态**：Phase 1 已完成（2026-03-17）；Phase 2 待建设  
**范围**：guofan 项目目录结构整理、模型档案标准化、openclaw 可发现性

---

## 一、问题陈述

当前目录存在三类混放问题，导致：
1. AI 接手时需要大量探索才能定位已有结果
2. openclaw 无法快速获取"哪些模型已完成评估、结论是什么"
3. 数据处理日志、benchmark 运行日志、模型档案散落在不同目录且缺少索引

| 目录 | 当前问题 |
|------|---------|
| `logs/` | benchmark 运行目录、nohup 日志、数据处理日志三类混放 |
| `datas/` | 原始业务 JSONL/CSV 源文件与处理后 `output_*/` 目录混放；源文件将迁移至外部 |
| `results/models/` | tianji 有完整 EVAL_REPORT.md，guoxue 缺失；无统一入口索引 |

---

## 二、设计目标

1. **最小改动原则**：不破坏正在运行中的脚本和现有链接
2. **openclaw 可发现性**：新增一个单一入口文件，openclaw 读一个文件即可了解全局状态
3. **模型档案完整性**：每个评估完成的模型都有 EVAL_REPORT.md（= model-card）
4. **阶段性交付**：Phase 1 今天可完成，Phase 2 待下次建设

---

## 三、目录结构变更规范

### 3.1 `logs/` — 仅分离数据处理日志

**变更**：新建 `logs/data-pipeline/`，将数据处理脚本产生的 `.log` 移入；benchmark 相关目录和日志保持原位。

```
logs/
  # ── benchmark 运行产物（不动）──────────────────
  guoxue_8tp_qps_20260316_163202/        ← 原始 QPS 档位目录（含 result.csv）
  guoxue_8tp_qps_20260316_163202.log     ← 配对的 nohup 输出日志
  tianji_*.../                           ← 同上
  ziwei_*.../                            ← 同上

  # ── 新增子目录 ─────────────────────────────────
  data-pipeline/                         ← 数据处理脚本日志
    process_guoxue_20260316_162108.log
    process_*.log（未来所有处理日志归此）

  archive/                               ← 已有，保持不动
```

**迁移规则**：

| 文件 | 操作 | 说明 |
|------|------|------|
| `process_guoxue_20260316_162108.log` | → `logs/data-pipeline/` | 数据处理脚本日志 |
| `guoxue_qps_20260316_163202.log` | → `logs/data-pipeline/` | sweep 协调脚本 stdout（注意：与 `guoxue_8tp_qps_20260316_163202.log` 是两个不同文件） |
| `guoxue_8tp_qps_20260316_163202.log` | **不动** | benchmark 工具 nohup 输出，与同名目录配对 |
| 其余所有 `{name}_{date}.log` | **不动** | 均与同名运行目录配对 |

**脚本更新**：`run_guoxue_8tp_qps_sweep.sh` 及未来脚本，process log 输出路径改为 `logs/data-pipeline/`

---

### 3.2 `datas/` — 文档化迁移计划，暂不移动文件

当前原始源文件（JSONL / CSV）将陆续迁移至 `/mnt/ai-infra/datasets/used4evaluation/`。

**现阶段**：不移动任何文件（避免影响运行中脚本），只在 `datas/README.md` 中标注迁移状态。

```
datas/
  # ── 源文件（将迁移至 /mnt/ai-infra/datasets/used4evaluation/）──
  hepan_all_0302_0304.jsonl                         ← 待迁移
  xinghan-guoxue-72b-v1-2-reason_260313_260314.jsonl  ← 待迁移
  xinghan-ziwei-32b-v1-1_260303_260305.jsonl          ← 待迁移
  tianji-querysafety-4b-v2-3_*.csv                   ← 待迁移
  tianji-querysafety-v2-3-system_prompt.txt           ← 待迁移

  # ── 处理后输出目录（长期保留在此）──────────────
  output_guoxue/
  output_henpan_tarot/
  output_tianji_querysafety/
  output_ziwei/

  README.md   ← 更新：标注每个文件的迁移状态和目标路径
```

---

### 3.3 `results/` — 不重组，仅完善 `models/` 层

`results/` 顶层实验目录（`hepan_benchmark_20260312/` 等）结构清晰、已有 README.md 索引，**不做重组**。

重点补全 `results/models/` 层：

```
results/
  models/
    INDEX.yaml                          ← 【新增】openclaw 入口索引
    tianji-querysafety-4b-v2-3/
      model-context.md                  ← 已有
      EVAL_REPORT.md                    ← 已有
    xinghan-guoxue-72b-v1-2-reason/
      model-context.md                  ← 已有
      EVAL_REPORT.md                    ← 【待补全，Step 6/7 完成后生成】
  README.md                             ← 已有，添加 INDEX.yaml 说明
  hepan_benchmark_20260312/             ← 不动
  ...（其余实验目录不动）
```

---

## 四、INDEX.yaml 规范

**路径**：`results/models/INDEX.yaml`  
**维护方式**：每次模型评估完成（Step 7）后手动/AI 追加一条记录  
**用途**：openclaw 读取此文件获取所有已评估模型的全局状态

**`linked_experiments` 字段说明**：指向该模型所有相关实验的结果目录（`results/` 下已分析的实验）。对于 `in_progress` 模型，若 `results/` 产物尚未生成，临时填写 `logs/` 运行目录作为占位，Step 6 完成后务必更新为 `results/` 路径。

```yaml
# guofan 项目模型评估索引
# 更新规则：每次 Step 7 完成后追加，status 字段由 AI 在工作流中更新

models:
  - model_name: tianji-querysafety-4b-v2-3
    model_type: 安全拦截模型
    eval_status: completed           # pending / in_progress / completed
    eval_completed_date: 2026-03-16
    deployment:
      tp_size: 4
      dp_size: 1
      gpu_type: L20
    performance:
      sla_max_qps_rps: 8.0
      sla_max_qps_rpm: 480
      sla_criterion: "E2E P95 ≤ 400ms"
      replay_success_rate: 100.0
      replay_e2e_p90_s: 0.236
    recommendation: "✅ 可上线，推荐 6 实例 × 4TP（业务峰值 2168 RPM，含 10% 余量）"
    paths:
      model_context: results/models/tianji-querysafety-4b-v2-3/model-context.md
      eval_report: results/models/tianji-querysafety-4b-v2-3/EVAL_REPORT.md
    linked_experiments:
      - results/tianji_querysafety_benchmark_20260312
      - results/tianji_querysafety_4tp_fullrange_20260313
      - results/tianji_querysafety_4tp_vs_4dp_filtered_20260313

  - model_name: xinghan-guoxue-72b-v1-2-reason
    model_type: 推理对话模型
    eval_status: in_progress         # Step 5 QPS Sweep 运行中
    eval_completed_date: null
    deployment:
      tp_size: 8
      dp_size: 1
      gpu_type: H100
    performance: null                # Step 6/7 完成后填写
    recommendation: null
    paths:
      model_context: results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md
      eval_report: null              # Step 7 完成后更新
    linked_experiments:
      - results/guoxue_partial_20260317    # 部分 Sweep 初步分析结果（Step 6 完成后更新/补充）
      # Step 5 运行中，以下为原始运行目录占位，Step 6 完成后替换为 results/ 正式实验目录
      - logs/guoxue_8tp_qps_20260316_163202
```

---

## 五、model-card 与 EVAL_REPORT.md 的关系

**结论**：二者是同一件事，不新建独立的 model-card 文件。

| 概念 | 实体 | 位置 |
|------|------|------|
| model-card（技术档案） | `EVAL_REPORT.md` | `results/models/{model}/EVAL_REPORT.md` |
| 增量结构化上下文（AI 工作流内部） | `model-context.md` | `results/models/{model}/model-context.md` |
| 全局索引（openclaw 入口） | `INDEX.yaml` | `results/models/INDEX.yaml` |

`EVAL_REPORT.md` 已覆盖 I1 中 model-card 提出的全部字段（部署配置、行为特征、压测结论、已知问题）。后续直接用 `model-eval-report` Skill 生成，不另建格式。

---

## 六、openclaw 接管使用路径

openclaw 接手项目时，推荐读取顺序：

```
1. results/models/INDEX.yaml       → 了解全局：哪些模型已完成、结论汇总
2. results/models/{name}/EVAL_REPORT.md  → 单个模型详情（部署配置、压测结论、资源建议）
3. results/README.md               → 实验目录索引（哪些 benchmark 实验对应哪个模型）
4. clingo/docs/workflow/model-onboarding.md  → 了解评估流程 SOP
```

Phase 2（HTTP API）建成后，openclaw 改为调用 `GET /api/models` 接口，不再直接读文件。

---

## 七、Skills 更新

| Skill | 需要更新的内容 | 状态 |
|-------|--------------|------|
| `model-evaluation-workflow` | Step 5 nohup 路径改为 `logs/data-pipeline/`；Step 7 完成后写 `INDEX.yaml` | ✅ 已完成（`cfda6da`）|
| `qps-benchmark-sweep` | 新增"多段扫描合并流程"章节；执行命令路径改为 `logs/data-pipeline/` | ✅ 已完成（`cfda6da`）|
| `benchmark-result-analysis` | 无需改动（results/ 结构不变）| — |
| `traffic-dataset-prep` | 无需改动（datas/ 不移文件）| — |

---

## 八、不在此次范围内（Phase 2）

- HTTP API 服务（FastAPI）
- 自动生成 `DASHBOARD.html`
- `datas/` 源文件向 `/mnt/ai-infra/datasets/used4evaluation/` 的实际迁移
- `results/experiments/` 子目录重组（等评估工作基本完成后统一归档）

---

## 九、执行清单（Phase 1）

- [x] 新建 `logs/data-pipeline/`，迁移以下文件：
  - `logs/process_guoxue_20260316_162108.log` → `logs/data-pipeline/`
  - `logs/guoxue_qps_20260316_163202.log` → `logs/data-pipeline/`
  - 未来所有 `process_*.log` 默认输出到此目录
- [x] 更新 `scripts/benchmark/run_guoxue_8tp_qps_sweep.sh`，将 process/协调 log 输出路径改为 `logs/data-pipeline/`（`cfda6da`）
- [x] 更新 `datas/README.md`：为每个源文件（JSONL / CSV）添加迁移目标路径 `/mnt/ai-infra/datasets/used4evaluation/{model}/`
- [x] 确认 `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` 已存在（Step 4 时已创建，无需补建）
- [x] 创建 `results/models/INDEX.yaml`（按 §4 规范：tianji 完整条目 + guoxue 占位条目）
- [x] 更新 `results/README.md`：快速导航首行改为 INDEX.yaml 链接，置顶为 openclaw 入口（`cfda6da`）
- [x] 更新 `model-evaluation-workflow` Skill，两处修改（`cfda6da`）：
  - **Step 5**：nohup 路径改为 `logs/data-pipeline/`
  - **Step 7**：完成后更新 `results/models/INDEX.yaml` 对应字段
- [x] 更新 `qps-benchmark-sweep` Skill：新增"多段扫描合并流程"章节，执行命令路径改为 `logs/data-pipeline/`（`cfda6da`，执行时发现的补充项）
- [ ] **待 guoxue Sweep 完成后**（预计 2026-03-17 ~18:00）：
  - 运行 Step 6：`offline_analysis.py` + `qps-sweep-comparison` Skill
  - 运行 Step 7：`model-eval-report` Skill 生成 `EVAL_REPORT.md`
  - 更新 `INDEX.yaml` guoxue 条目（`eval_status: completed`，填写 performance / recommendation）
