# 过番（Guofan）—— 模型部署迁移行动

> **行动代号来源**：「过番」源自闽南方言，指历史上福建、广东一带民众漂洋过海、南下谋生的移民浪潮，即「下南洋」。
> 旧土难以为继，便整装出发，在异乡重建家园。
> 本项目取此典故，寓意公司内部模型部署服务的系统性迁移——从旧基础设施启程，在新平台上稳定落地。

---

## 项目动机

随着业务规模的持续扩张，现有的模型部署服务在可维护性、资源利用率以及推理框架的统一性上均面临瓶颈。为此，我们启动「过番」迁移专项，目标是将所有在线推理服务系统性地迁移至基于 **SGLang** 的裸模型部署方案，在新的基础设施平台上完成稳定运营。

正如当年漂洋过海的先辈，迁移之路并不轻松——但走出去，才能在更广阔的地方扎根。

---

## 迁移进度总览

| 服务 / 模型 | 数据处理 | 本地部署 | 平台部署 | 压测 | 分析报告 | 状态 |
|---|---|---|---|---|---|---|
| `tianji-querysafety-4b-v2-3` | ✅ | ✅ | ✅ bakv1 | ✅ 回放 1422 RPM + QPS sweep | ✅ | **已完成** |
| `xinghan-ziwei-32b-v1` | ✅ | ✅ | ✅ | ✅ QPS sweep（TP4 + TP8 对比）| ✅ | **已完成** |
| `ziwei-intention-twostep-8b-v1` | ✅ | ✅ | ✅ | ✅ | ✅ | **已完成** |
| `xinghan-hepan-72b-v1` | ✅ | ⏳ 同事负责 | ✅ | ✅ 回放 150 RPM + QPS sweep | ✅ | **压测完成** |

---

## 工程工具体系（Cursor Agent Skills）

本项目在迁移过程中同步建设了一套可复用的 AI Agent 作业技能，支持后续模型的快速评估上线：

| Skill | 功能 | 状态 |
|---|---|---|
| `traffic-dataset-prep` | 从业务日志提取峰值窗口、泊松插值、生成压测数据集 | ✅ 已验证 |
| `llm-deployment-docker` | Docker + SGLang 本地部署，含 VRAM 预检、健康轮询、冒烟测试 | ✅ 已验证 |
| `llm-service-probing` | 无业务数据时自动检测模型类型（安全过滤 / 路由 / 对话）| ✅ 已验证 |
| `llm-replay-benchmark` | 按真实流量时间戳回放压测，验证峰值承载能力 | ✅ 已验证 |
| `qps-benchmark-sweep` | QPS 阶梯扫描，定位服务容量拐点 | ✅ 已验证 |
| `benchmark-result-analysis` | 离线分析压测日志，输出 CDF 图表 + HTML 报告 + REPORT.md | ✅ 已验证 |
| `qps-sweep-comparison` | 多组 QPS sweep 结果可视化对比（如 TP4 vs TP8）| ✅ 已验证 |

---

## 目录结构

```
guofan/
├── scripts/
│   ├── deploy/          # SGLang 本地启动脚本
│   ├── benchmark/       # QPS sweep / 回放压测脚本
│   ├── data/            # 数据处理脚本（峰值采样、泊松插值）
│   ├── probe/           # 模型能力探测脚本
│   ├── analysis/        # 离线分析脚本
│   └── serve.py         # 本地推理服务入口
├── results/             # 各模型分析报告（按需选择性提交）
├── clingo/
│   ├── docs/skills/     # Skill 文档库 + 路线图
│   ├── docs/workflow/   # 模型上线 SOP
│   └── sessions/        # 历次会话记录
├── .cursor/skills/      # Cursor Agent Skill 源文件
├── third_party/         # 第三方依赖（submodule）
├── progress.md          # 多会话进度日志
└── project_status.md    # 项目整体状态总结
```

> `logs/`（86GB）和 `datas/`（7.8GB）已通过 `.gitignore` 排除，不纳入版本控制。

---

## 关键字段说明

| 字段 | 说明 |
|---|---|
| `RPM` | Requests Per Minute，每分钟请求量 |
| `QPS sweep` | 阶梯式 QPS 扫描测试，用于定位服务容量拐点 |
| `TTFT / TTFS` | Time to First Token / Time to First Streaming chunk |
| `E2E` | 端到端响应延迟（从发送到接收完整响应）|
| `TP` | Tensor Parallelism，张量并行度 |
| `裸模型` | 仅包含模型推理能力、不含业务逻辑的纯推理服务 |
| `切流` | 将线上请求从旧服务平滑切换至新服务的操作 |

---

## 联系人

| 角色 | 负责人 |
|---|---|
| 运维（Deployment） | 王倪东 |
| 算法（天玑） | 刘尧 |
| 算法（紫微 / 天玑闲聊）| 刘奇、黄继豪 |
| 数据（AIData） | 刘尧（临时）|

---

*「番客不怕苦，落番才有路。」——愿过番顺遂，新土安稳。*
