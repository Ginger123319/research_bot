# 项目文档中心

> 模型部署迁移评估工程 — 文档索引  
> 更新：2026-03-13

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
流量回放测试（真实请求回放）
    ↓
QPS 拐点扫描 & 压力测试
    ↓
结果分析 & 量化报告
```

这套链路针对每个新模型**完全可重复**，是本工程 Skill 化的核心价值。

---

## 目录结构

```
clingo/docs/
├── README.md                    # 本文件，项目概览 + 文档索引
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
    ├── qps-benchmark-sweep/      # ✅ QPS 扫描 Skill
    ├── qps-sweep-comparison/     # ✅ QPS 多组对比分析 Skill
    ├── llm-replay-benchmark/     # ✅ 流量回放 Skill
    ├── benchmark-result-analysis/# ✅ 结果分析 Skill
    └── model-evaluation-workflow/# ✅ 顶层流程编排 Skill
```

> 待建：`workflow/reporting-template.md`、`models/` 模型档案目录（见 planning/need-todo-idea.md）

---

## 已跑通的模型清单

| 模型 | 类型 | 部署配置 | 状态 |
|------|------|----------|------|
| xinghan-ziwei-32b-v1 | 通用对话 | TP=4, GPU 1,3,4,5, :5290 | ✅ 全流程完成（QPS/回放/报告）|
| ziwei-intention-twostep-8b | 意图分类/路由 | TP=1, GPU 7, :5291 | ✅ 全流程完成 |
| xinghan-hepan-72b-v1-2 | 通用对话 | TP=4（NVLink 机器）| ✅ 全流程完成（150 RPM 回放，QPS 0.80 req/s）|
| tianji-querysafety-4b-v2-3 | 安全拦截 | DP=4 TP=1（PCIe 推荐）, :8361 | ✅ 全流程完成（回放 100%，QPS 4TP vs 4DP 对比）|

---

## Skill 体系现状（8 个已完成）

| Skill | 用途 | 状态 |
|-------|------|------|
| `traffic-dataset-prep` | JSONL 日志 → 压测 CSV（6步管道）| ✅ 已验证 |
| `llm-deployment-docker` | Docker 部署 + 预检 + 健康检查 | ✅ 已验证 |
| `llm-service-probing` | 服务能力自动探测 + 模型类型判断 | ✅ 已验证 |
| `qps-benchmark-sweep` | QPS 拐点扫描脚本设计与执行 | ✅ 已验证 |
| `qps-sweep-comparison` | 多组 QPS 结果对比可视化 + SLA 评估 | ✅ 已验证 |
| `llm-replay-benchmark` | 真实流量回放 + 峰值验证 | ✅ 已验证 |
| `benchmark-result-analysis` | 离线分析 + HTML/PNG + REPORT 骨架 | ✅ 已验证 |
| `model-evaluation-workflow` | 新模型接入顶层编排（两阶段+人工断点）| ✅ 完成 |

---

## 快速导航

- 规划讨论 → [`planning/need-todo-idea.md`](planning/need-todo-idea.md)
- Skill 建设路线图 → [`planning/skills-roadmap.md`](planning/skills-roadmap.md)
- 新模型接入流程 → [`workflow/model-onboarding.md`](workflow/model-onboarding.md)
- 设计规格文档 → [`designs/`](designs/)
