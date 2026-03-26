# 过番（Guofan）—— 模型部署迁移行动

> **行动代号来源**：「过番」源自闽南方言，指历史上福建、广东一带民众漂洋过海、南下谋生的移民浪潮，即「下南洋」。
> 旧土难以为继，便整装出发，在异乡重建家园。
> 本项目取此典故，寓意公司内部模型部署服务的系统性迁移——从旧基础设施启程，在新平台上稳定落地。

---

## 项目动机

随着业务规模的持续扩张，现有的模型部署服务在可维护性、资源利用率以及推理框架的统一性上均面临瓶颈。为此，我们启动「过番」迁移专项，目标是将所有在线推理服务系统性地迁移至基于 **SGLang** 的裸模型部署方案，在新的基础设施平台上完成稳定运营。

---

## 迁移进度总览

### 高优（本周完成评估）

| 服务名 | 模型 | 迁移策略 | 总卡数 | 迁移进度 | 评估状态 | 算法负责 | 业务归属 |
|---|---|---|---|---|---|---|---|
| `tianji-query-safety-4b-v1-1-cmic` | tianji-querysafety-4b-v2-3 | 直接迁移·裸模型部署 | 32（8副本×4卡）| ✅ 已完成 | ✅ 测试通过 | 刘尧 | 天玑-Query安全改写 |
| `xinghan-ziwei-32b-v1-cm` | xinghan-ziwei-32b-v1-1 | 直接迁移·分离部署 | 16（2副本×8卡）| ✅ 已完成 | ✅ 部署+压测通过 | 刘奇 | 紫微-普通-32B |
| `ziwei-intention-twostep-8b-v1-cm` | ziwei-intention-twostep-8b-v1 | 直接迁移·裸模型部署 | 4（4副本×1卡）| ✅ 已完成 | ✅ 部署完成 | 刘奇 | 算法内部服务 |

### 中优（下周计划）

| 服务名 | 模型 | 迁移策略 | 总卡数 | 迁移进度 | 当前阻塞 | 算法负责 | 业务归属 |
|---|---|---|---|---|---|---|---|
| `xinghan-deploy-v1-1-agent` | xinghan-chart-32b-v1-1-agent | 延后迁移·混部，待工程改造 | 24（3副本×8卡）| 待切流 | ✅ 评估完成（V2，8TP 回放 100%）；工程改造进行中 | 黄继豪 | 星盘-普通-32B |
| `xinghan-deploy-v1-1-dpagent` | — | ~~延后迁移~~ | 2（2副本×1卡）| ❌ 取消 | 算法确认无需部署 | 黄继豪 | 星盘-普通-32B |
| `ceceai-model-vllm-intent-recognition-v1-1` | intent-recognition-v1.1 | 延后迁移·混部，待工程改造 | 2（2副本×1卡）| 待开始 | 算法内部服务，八字/星盘通用 | 刘昕洋 | 玄学工具内部-意图识别 |

---

## 各服务评估结果摘要（高优）

### tianji-querysafety-4b-v2-3

- **新服务地址**：`https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23/`
- **推理框架**：SGLang `v0.4.6.post2`，镜像 `reg.xxwolo.com/master/sglang:v0.4.6.post2`
- **压测结论**：回放峰值 1422 RPM，成功率 100%，E2E 均值 0.214s，TTFS 均值 0.210s
- **QPS sweep**：4TP 单实例容量拐点约 35 req/s（≈ 2100 RPM），满足当前 567 RPM 业务峰值需求
- **备注**：缩容方案（8副本→4副本），报告见 `results/tianji_querysafety_*/`

### xinghan-ziwei-32b-v1-1

- **新服务地址**：`https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1/`
- **推理框架**：SGLang `v0.4.1.post4`
- **压测结论**：回放 100 RPM 成功率 100%；TP4 vs TP8 QPS sweep 对比完成
- **备注**：交接工程后自动完成裸模型拆分，报告见 `results/ziwei_*/`

### ziwei-intention-twostep-8b-v1

- **新服务地址**：`https://infer.geniuworks.com/infra-ziwei-intention-twostep-p8b-v1/`
- **推理框架**：SGLang `v0.4.6.post2`
- **压测结论**：算法内部服务，按 Dockerfile 原资源量直接部署，无需回放测试
- **备注**：意图分类路由层，completion ≈ 8 tokens，响应极快（~0.2s）

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
| 算法（星盘 / 玄学）| 黄继豪、刘昕洋 |
| 数据（AIData） | 刘尧（临时）|

---

*「番客不怕苦，落番才有路。」——愿过番顺遂，新土安稳。*
