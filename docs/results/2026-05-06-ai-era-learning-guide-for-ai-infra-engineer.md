# 调研报告：AI 编程时代，AI-infra 工程师应该学什么

> 调研日期：2026-05-06
> 适用对象：AI-infra 工程师（核心：推理优化 / 训练优化 / 训练框架开发；偶发：Web 应用开发）
> 输出形式：结构化分析报告 + 可执行的精力分配建议

---

## 结论摘要

1. **推理优化是 2026 年最值得深耕的核心方向**：推理负载已超过训练，占 AI 优化基础设施支出的 55%+，且仍在增长。KV cache 管理、spec decoding、多节点分布式推理是最具稀缺性的技术壁垒。

2. **CUDA/Triton kernel 开发是最难被 AI 替代的技能**：AI 工具可以生成脚手架代码，但无法在硬件约束下做出精确的性能决策。这是与底层硬件深度耦合的"手艺型"技能，越精通价值越高。

3. **Web 开发只需学到"能读懂、能指挥 AI"的程度**：AI 编程工具（Cursor + v0 + Claude）已可以完成 80% 的前端实现工作。对于非前端专职工程师，目标是"能写精确 spec、能验证 AI 输出"，而非深学框架细节。

4. **工作方式的核心转变：从"写代码者"变成"架构决策者 + AI 任务编排者"**：编码时间已从占工作日 55% 降至 20%。精力应转移到系统设计、性能边界判断、AI 输出的正确性审查。

5. **MoE 架构基础设施和 Agentic 工作负载是两个值得提前布局的新方向**：MoE 已成为高性能开源模型的标准范式，带来专家路由、负载均衡等新的系统挑战。

---

## 一、AI 编程工具真正改变了什么

### 1.1 工作时间分布的重塑

AI 编程工具普及后，工程师的工作重心发生了结构性变化：

| 工作类型 | 2023 年占比 | 2026 年占比 |
|---------|------------|------------|
| 编写代码 | ~55% | ~20% |
| 代码审查 / AI 输出验证 | ~10% | ~35% |
| 架构设计 / 系统思考 | ~20% | ~35% |
| 文档 / 沟通 / 其他 | ~15% | ~10% |

每周 AI 代码审查时间已达 11.4 小时。**能快速判断 AI 生成代码质量**，成为新的核心生产力。

### 1.2 AI 擅长什么，仍然做不到什么

**AI 能做好的：**
- 样板代码生成（Dockerfile、CI 配置、测试框架）
- 错误信息诊断与解释
- Shell 脚本和正则表达式
- 已知模式的重构

**AI 做不好的（人的不可替代区）：**
- **上下文感知**：不了解你的系统架构、硬件约束、团队命名规范
- **系统间依赖推理**：无法维持跨组件修改的全局一致性心智模型
- **权衡判断**：架构层面的 trade-off 需要人来拍板
- **硬件-软件协同优化**：CUDA kernel 的精细调优依赖对具体硬件微架构的深度理解

---

## 二、AI-infra 核心方向：哪些能力 AI 无法替代

### 2.1 推理优化（2026 年最核心的战场）

推理已在 2026 年超越训练，成为 AI 基础设施支出的主体（>55%，预计年底达 70-80%）。核心技术壁垒：

| 技术方向 | 重要性 | 核心要点 |
|---------|--------|---------|
| KV Cache 管理 | ⭐⭐⭐⭐⭐ | PagedAttention、KV cache 共享、前缀缓存、跨请求复用 |
| Speculative Decoding | ⭐⭐⭐⭐⭐ | 最高可提升 9.9x TTFT，理解 draft model 选择与接受率调优 |
| 连续批处理（Continuous Batching） | ⭐⭐⭐⭐ | 动态调度、吞吐量与延迟的权衡 |
| 多节点分布式推理 | ⭐⭐⭐⭐ | Tensor Parallel、Pipeline Parallel、Expert Parallel（MoE 场景） |
| MoE 推理优化 | ⭐⭐⭐⭐ | Expert routing、Expert load balancing、Token dropping |
| 量化技术（AWQ/GPTQ/FP8） | ⭐⭐⭐⭐ | 精度-性能 trade-off、硬件感知量化 |

**重点框架**（2026 年必须掌握）：
- `vLLM`：生产部署最广泛，PagedAttention 的参考实现
- `SGLang`：RadixAttention + 结构化生成，新兴主流
- `NVIDIA Dynamo 1.0`（2026.03 发布）：分布式推理操作系统，集成 KVBM / NIXL / Grove，支持 7x 性能提升

### 2.2 CUDA / Triton Kernel 开发（最难被替代的技艺）

这是 AI-infra 工程师的"稀缺壁垒"。AI 工具可以生成 kernel 框架代码，但以下判断仍需人来做：

- **访存模式优化**：shared memory 使用、bank conflict 避免、coalesced access 设计
- **Warp-level 并行策略**：warp divergence 控制、register 分配权衡
- **硬件特性利用**：Tensor Core 调用（cuBLAS/CUTLASS）、L2 cache 管理
- **性能 profiling 解读**：用 Nsight Compute 分析 kernel bottleneck

**Triton** 正快速成为生产主流（FlashAttention-3 已部分用 Triton 实现），建议在掌握 CUDA 基础后重点投入 Triton，开发效率显著更高。

**TensorRT-LLM CUDA kernels** 已开源贡献至 FlashInfer，建议阅读其实现作为学习材料。

### 2.3 训练优化（保持而非深挖）

训练优化仍是重要技能，但在 2026 年不是增长最快的需求点。维持当前水准，跟进关键进展即可：

- **分布式训练**：3D 并行（Data / Tensor / Pipeline）、ZeRO 优化器系列
- **显存优化**：梯度检查点、激活重计算、混合精度（BF16 为主）
- **通信优化**：NCCL 调优、All-reduce 与 All-gather 的使用场景

**值得关注的新动向**：
- **Megatron-Core** 模块化架构（替代 Megatron-LM 的旧版本）
- **FSDP2**（PyTorch 2.x）：更灵活的全分片策略
- **训练框架向推理框架融合**：同一套代码同时支持训练和推理部署

### 2.4 训练框架开发（深度方向）

框架开发需要的系统性能力：

| 能力 | 说明 |
|------|------|
| Python/C++ 混合开发 | PyTorch 算子扩展（`torch.autograd.Function`、`pybind11`） |
| 计算图理解 | `torch.compile`、`torch.fx`、计算图 pass 优化 |
| 分布式通信原语 | `torch.distributed` 底层 API、collective 通信实现 |
| 自定义调度器 | 异步 pipeline、micro-batch 调度策略 |

---

## 三、Web 开发：AI 时代学到什么程度够用

### 3.1 重新定义"够用"

对 AI-infra 工程师而言，Web 开发的目标不是"能独立搭建完整前端工程"，而是：
> **"能用自然语言 + 精确 spec 指挥 AI 实现功能，并能识别输出中的逻辑错误"**

### 3.2 必须懂的（无论 AI 多强大都要知道）

- **HTTP 基础**：请求/响应模型、RESTful 设计、状态码含义
- **前端三件套概念**：HTML 结构 / CSS 样式 / JS 行为的职责边界
- **React 组件思维**：props、state、副作用（useEffect）——足以理解 AI 生成的组件代码
- **异步 JS 基础**：Promise / async-await，理解 API 调用流程

### 3.3 交给 AI 做就好（无需深学）

- CSS 具体属性记忆（Flexbox 细节、动画写法）
- Webpack / Vite 配置
- UI 组件库的具体 API（shadcn/ui、MUI 等）
- 状态管理框架（Redux、Zustand 的内部实现）

### 3.4 推荐工具链（让 AI 发挥最大价值）

| 工具 | 用途 |
|------|------|
| **Cursor** | 主力 IDE，Agent 模式处理多文件修改 |
| **v0 by Vercel** | UI 原型快速生成，一句话出完整组件 |
| **Claude / GPT-4o** | 复杂逻辑的架构设计辅助 |
| **Next.js** | 最适合内部工具的全栈框架，约定大于配置 |

**实操建议**：遇到 Web 开发需求时，先用 v0 生成 UI 原型，再用 Cursor 接入后端逻辑，全程以"reviewer"而非"writer"的身份工作。

---

## 四、如何构建「人 + AI」的协作方法论

### 4.1 心智模型的转变：从"编码者"到"编排者"

不再是写代码给 AI 看，而是**把工程任务分解为 AI 可以并行执行的子任务**，人负责：
- 定义架构边界和性能约束
- 审查 AI 输出是否符合系统上下文
- 处理跨模块的一致性和依赖关系

### 4.2 Context Engineering（上下文工程）

这是 2026 年最重要的元技能。给 AI 的上下文质量决定输出质量：

**高质量上下文应包含：**
```
- 硬件环境（GPU 型号、显存容量、互联带宽）
- 性能目标（目标吞吐 / 延迟 SLA）
- 现有接口约束（API 签名、数据格式）
- 已知限制（不可更改的依赖版本、安全策略）
```

**差的上下文 vs 好的上下文示例：**

❌ 差："帮我优化这个 CUDA kernel"

✅ 好："这是一个在 A100 (80GB) 上运行的 attention kernel，当前 occupancy 只有 42%，Nsight 显示 L2 cache miss 率 78%，目标是在 batch=32、seq=2048 下将吞吐提升到 2x，现有代码不能改变函数签名"

### 4.3 多 Agent 并行工作流

```
你（架构决策者）
    ├── Agent A：实现 kernel 优化（隔离分支）
    ├── Agent B：编写 benchmark 测试代码
    └── Agent C：更新文档和接口说明
```

每日使用 AI 工具的工程师合并 PR 数比不使用者高 **60%**，高级用户（多 Agent 工作流）报告 10-20x 速度提升。

### 4.4 AI 输出的验证框架

特别在 AI-infra 领域，AI 生成的性能代码需要额外验证：

| 验证维度 | 检查要点 |
|---------|---------|
| **正确性** | 数值精度、边界条件、异常处理 |
| **性能声明可信度** | AI 经常虚报加速比，必须实测 |
| **安全性** | IAM 权限、网络暴露面、敏感数据 |
| **系统一致性** | 是否与现有架构的隐式约定冲突 |

---

## 五、2026 年值得提前布局的新方向

| 方向 | 成熟度 | 建议投入 |
|------|--------|---------|
| **MoE 推理基础设施** | 生产早期 | 中等深度，理解 expert routing 挑战 |
| **多模态推理优化** | 快速增长 | 跟进，了解视觉/音频 token 处理特殊性 |
| **Agentic 工作负载基础设施** | 快速增长 | 了解 compound AI 的 memory、retrieval 需求 |
| **KV Cache 跨会话管理** | 生产中 | 重点，跨请求共享是推理成本优化关键 |
| **边缘/混合部署** | 增长 | 了解云-边调度策略 |
| **AI 编译器（XLA/Triton compiler）** | 深水区 | 按需，有训练框架需求时深入 |

---

## 六、精力分配建议

基于以上分析，建议 AI-infra 工程师按以下比例分配学习精力：

```
推理优化（KV cache、spec decoding、分布式推理）  ████████████  35%
CUDA/Triton kernel 开发与调优                    ████████      25%
训练优化与框架开发（维持 + 跟进新动向）            ████████      25%
「人+AI」工作方法论（context eng、多 Agent 流）    ████          10%
Web 开发（概念理解 + 工具熟练）                    ██            5%
```

---

## 七、调研局限性

- **Web 开发部分**置信度为中等：未能具体了解用户偶发 Web 开发需求的具体场景（内部工具 vs 面向用户产品），建议按实际场景调整
- **薪资数据** 来自美国市场，与国内情况存在差异，仅供参考
- **NVIDIA Dynamo 1.0** 相关数据来自官方资料，实际生产采用情况待观察
- **训练框架开发**部分的新动向覆盖不全，Megatron-Core 与 FSDP2 的实际差异需要实测验证

---

## 参考来源

1. [AI Coding Assistants Will Change DevOps — But Not in the Way You Think | DevOpsBoys](https://devopsboys.com/blog/ai-coding-assistants-will-change-devops-2026)
2. [The impact of AI on software engineers in 2026: key trends | Pragmatic Engineer](https://newsletter.pragmaticengineer.com/p/the-impact-of-ai-on-software-engineers-2026)
3. [AI Infrastructure Shifts in 2026 | Unified AI Hub](https://www.unifiedaihub.com/blog/ai-infrastructure-shifts-in-2026-from-training-to-continuous-inference)
4. [The new equation: What AI leaders need to know about infrastructure in 2026 | Crusoe AI](https://www.crusoe.ai/resources/blog/the-new-equation-what-ai-leaders-need-to-know-about-infrastructure-in-2026)
5. [AI Infrastructure Roadmap: Five frontiers for 2026 | Bessemer Venture Partners](https://www.bvp.com/atlas/ai-infrastructure-roadmap-five-frontiers-for-2026)
6. [NVIDIA Dynamo 1.0 Powers Multi-Node Inference at Production Scale | NVIDIA Technical Blog](https://developer.nvidia.com/blog/nvidia-dynamo-1-production-ready/)
7. [Multi-Agent AI Coding Workflow: The Complete Guide | Agentic Blog](https://blog.appxlab.io/2026/04/06/multi-agent-ai-coding-workflow/)
8. [Claude Code Guide 2026: Context Engineering & Planning | Generative, Inc.](https://www.generative.inc/the-complete-claude-code-guide-2026-planning-context-engineering-and-high-leverage-development)
9. [Ask HN: How to learn CUDA to professional level | Hacker News](https://news.ycombinator.com/item?id=44216123)
10. [AI Coding Tool Adoption 2026: Developer Survey Results | Digital Applied](https://www.digitalapplied.com/blog/ai-coding-tool-adoption-2026-developer-survey)
