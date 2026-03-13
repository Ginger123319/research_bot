# 项目文档中心

> 模型部署迁移评估工程 — 文档索引

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
├── README.md                   # 本文件，项目概览 + 文档索引
├── need-todo-idea.md           # 需求 / 待办 / 想法（规划讨论文档）
├── workflow/
│   ├── model-onboarding.md     # 新模型接入 SOP（标准操作流程）
│   └── reporting-template.md  # 量化报告模板
├── skills/
│   └── skills-roadmap.md       # Skill 建设路线图（候选清单 + 优先级）
└── models/
    ├── ziwei-32b.md             # xinghan-ziwei-32b-v1 模型档案
    ├── ziwei-8b.md              # ziwei-intention-8b 模型档案
    └── tianji-querysafety-4b.md # tianji-querysafety-4b-v2-3 模型档案
```

---

## 已跑通的模型清单

| 模型 | 类型 | 部署配置 | 状态 |
|------|------|----------|------|
| xinghan-ziwei-32b-v1 | 对话响应 | TP=4, GPU 1,3,4,5, :5290 | ✅ 全流程完成 |
| ziwei-intention-8b | 意图分类 | TP=1, GPU 1, :5291 | ✅ 全流程完成 |
| tianji-querysafety-4b-v2-3 | 安全拦截 | TP=4→建议TP=1×DP=4, GPU 3,4,5,6, :8361 | 🔄 探测完成，回放待数据 |

---

## 快速导航

- 规划讨论 → [`need-todo-idea.md`](need-todo-idea.md)
- 新模型接入流程 → [`workflow/model-onboarding.md`](workflow/model-onboarding.md)
- Skill 建设路线图 → [`skills/skills-roadmap.md`](skills/skills-roadmap.md)
