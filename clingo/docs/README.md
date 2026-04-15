# 项目文档中心

> 模型部署迁移评估工程 — 文档索引  
> 更新：2026-03-26

## 项目定位

本工程用于**模型部署迁移的全流程评估**，核心工作链路：

```
新模型上线需求
    ↓
本地 Docker 容器部署 & 启动脚本
    ↓
服务探测 & 行为特征记录
    ↓
线上日志提取 → 数据清洗 → 测试数据集构建
    ↓
远端服务连通性验证
    ↓
QPS Peak Finder（三阶段：饱和探测 → 自适应逼近 → 生产网格验证）
    ↓
流量回放测试（真实请求回放，SLA 验证）
    ↓
结果分析 & 量化报告（EVAL_REPORT.md）
```

这套链路针对每个新模型**完全可重复**，是本工程 Skill 化的核心价值。

---

## 目录结构

```
clingo/docs/
├── README.md                    # 本文件，项目概览 + 文档索引
├── ai_data/                     # 模型数据结构说明（线上日志格式分析）
│   ├── xinghan-chart-32b-v1-1-agent-data-structure.md
│   └── xinghan-guoxue-72b-v1-2-reason-data-structure.md
├── planning/
│   ├── need-todo-idea.md        # 需求 / 待办 / 想法（规划讨论文档）
│   └── skills-roadmap.md        # Skill 建设路线图（候选清单 + 优先级）
├── designs/
│   └── 2026-03-13-llm-deployment-probing-design.md  # llm-deployment-docker + llm-service-probing 设计规格
├── workflow/
│   └── model-onboarding.md      # 新模型接入 SOP（标准操作流程，含 Skill 引用）
└── skills/                      # 每子目录 = 一个可执行 Skill（SKILL.md）
    ├── traffic-dataset-prep/     # ✅ 数据集构建 Skill
    ├── llm-deployment-docker/    # ✅ 本地 Docker 部署 Skill
    ├── llm-service-probing/      # ✅ 服务能力探测 Skill
    ├── qps-benchmark-sweep/      # ✅ QPS 扫描 Skill（旧版，已被 peak-finder 替代）
    ├── qps-peak-finder/          # ✅ QPS Peak Finder Skill（三阶段自适应）
    ├── qps-peak-finder-analysis/ # ✅ Peak Finder 结果分析 + REPORT 生成 Skill
    ├── qps-sweep-comparison/     # ✅ QPS 多组对比分析 Skill
    ├── llm-replay-benchmark/     # ✅ 流量回放 Skill
    ├── benchmark-result-analysis/# ✅ 单批次结果分析 Skill
    ├── model-eval-report/        # ✅ 交付报告生成 Skill（EVAL_REPORT.md）
    └── model-evaluation-workflow/# ✅ 顶层流程编排 Skill（Step 0~7）
```

---

## 已完成评估的模型

| 模型 | 硬件 | ideal_rps | 业务峰值 | QPS评估 | 回放测试 | EVAL_REPORT | 状态 |
|------|------|-----------|---------|---------|---------|-------------|------|
| xinghan-ziwei-32b-v1 | 8×L20 × 2实例 | 1.59 req/s (95.4 RPM) | 52 RPM | ✅ | ✅ 99.97% | ✅ | 🟢 已交付 |
| xinghan-hepan-72b-v1-2 | 8×L20 | — | — | ✅ | ✅ | ✅ | 🟢 已交付 |
| tianji-querysafety-4b-v2-3 | 4TP × 8实例 | 7.86 RPS (471 RPM/实例) | 3524 RPM (7日峰) | ✅ | ✅ 100% | ✅ | 🟢 已交付 |
| xinghan-chart-32b-v1-1-agent | 8×L20（8TP）| 3.83 req/s (230 RPM) | 118 RPM | ✅ V2 | ✅ 100% | ✅ | 🟢 已交付 |
| xinghan-guoxue-72b-v1-2-reason (vanilla) | 8×L20 / 4×H20 | L20: 0.2114 / H20: 0.5878 req/s | 256 RPM | ✅ | ✅ 99.89% | ✅ V2 | 🟢 已交付 |
| xinghan-guoxue-72b-v1-2-reason (Eagle3) | 8×L20 | 0.3169 req/s (+50%) | 256 RPM | ✅ | — | ⏳ 待追加章节 | 🟡 |
| lingyu-235b-A22b-v9-2 | — | — | 758 RPM | ✅ | ❌ 无数据 | ⏳ 待生成 | 🟡 |

---

## Skill 体系现状（11 个已完成）

| Skill | 用途 | 状态 |
|-------|------|------|
| `traffic-dataset-prep` | JSONL 日志 → 压测 CSV（6 步管道，含 agent_converted 格式）| ✅ |
| `llm-deployment-docker` | Docker 部署 + 预检 + 健康检查 | ✅ |
| `llm-service-probing` | 服务能力自动探测 + 模型类型判断 | ✅ |
| `qps-benchmark-sweep` | QPS 多档扫描（固定步进，适合已知拐点区间）| ✅ |
| `qps-peak-finder` | QPS Peak Finder 三阶段自适应（未知拐点首选）| ✅ |
| `qps-peak-finder-analysis` | Phase 1~3 数据合并、容量曲线、REPORT.md 生成 | ✅ |
| `qps-sweep-comparison` | 多组 QPS 结果对比可视化 + SLA 评估 | ✅ |
| `llm-replay-benchmark` | 真实流量回放 + 峰值 SLA 验证 | ✅ |
| `benchmark-result-analysis` | 单批次离线分析 + HTML/PNG + REPORT 骨架 | ✅ |
| `model-eval-report` | 交付报告生成（EVAL_REPORT.md，含部署建议）| ✅ |
| `model-evaluation-workflow` | 新模型接入顶层编排（Step 0~7，含断点检查）| ✅ |

---

## 快速导航

- 规划讨论 → [`planning/need-todo-idea.md`](planning/need-todo-idea.md)
- Skill 建设路线图 → [`planning/skills-roadmap.md`](planning/skills-roadmap.md)
- 新模型接入流程 → [`workflow/model-onboarding.md`](workflow/model-onboarding.md)
- 设计规格文档 → [`designs/`](designs/)
- 模型数据结构说明 → [`ai_data/`](ai_data/)
