# 调研报告：主流大模型训练框架及训练场景

> **调研日期**：2026-04-15
> **信息时效**：2025 - 2026 年公开资料
> **输出形式**：结构化报告 + 对比表 + 选型建议
> **适读对象**：AI 工程师 / 研究人员，有框架选型或场景适配需求

---

## 阅读路径引导

> 按以下三层路径阅读，总耗时约 1 小时，可覆盖报告 90% 的有效信息。

### 第一层：建立全局认知（~10 分钟）

先读「**结论摘要**」+ 「**第一节：主流框架全景**」中的三层架构图。

读完后用这句话自测：
> *"我当前的任务属于三层中的哪一层（预训练 / 微调 / 后训练）？"*

### 第二层：精读与你最相关的场景（~30 分钟）

直接跳到「**第三节：框架 × 训练场景映射表**」，找到你的训练场景行，然后回头精读对应框架的详细介绍：

| 关注点 | 精读章节 |
|-------|---------|
| 大规模预训练 / MoE 训练 | 第二节 2.1「Megatron-LM」+「DeepSpeed」 |
| SFT 微调 / LoRA 快速上手 | 第二节 2.2「LLaMA-Factory」+「Unsloth」 |
| RLHF / GRPO 后训练 | 第二节 2.3「verl」+「OpenRLHF」及架构差异 |
| 国产化 / 昇腾 NPU 环境 | 第二节 2.2「MS-SWIFT」 |
| 多模态训练 | 「MS-SWIFT」+「Axolotl」的多模态支持对比 |

精读时重点抓这 3 个关键数字：
- **10B 规则**：模型低于 10B 时 FSDP2 比 DeepSpeed ZeRO-3 快最高 5 倍（选型分水岭）
- **90%+**：RLHF 总时长中推理阶段的占比（解释了为什么 vLLM 在后训练框架中如此关键）
- **2x / 50-70%**：Unsloth 相比标准训练的速度提升倍数 / 显存节省比例（资源受限场景的核心参考）

### 第三层：校验判断与识别局限（~20 分钟）

阅读「**第五节：2026 年趋势展望**」，对每条趋势问自己：
> *"这个趋势对我当前的工作有影响吗？要不要现在跟进？"*

**局限性章节必读**（第六节）：部分性能 benchmark 来自框架官方，存在场景偏向；框架迭代极快，选型前需验证版本是否已更新。

### 容易被忽略的 3 个细节

- **verl 与 OpenRLHF 的本质分叉**（第二节 2.3）：verl 是工业部署优先（稳定、GPU 利用率 85%），OpenRLHF 是研究优先（算法多、代码易改）——这是 RLHF 框架选型最重要的一个判断点
- **DeepSpeed 是「搭档」而非「独立框架」**（第二节 2.1）：它几乎总是和 Megatron-LM、LLaMA-Factory 等搭配使用，单独选 DeepSpeed 并不完整
- **MS-SWIFT 的昇腾适配是唯一选择**（映射表国产化行）：目前没有其他框架在昇腾上有同等深度的适配，国产化环境下无需再做横向对比

### 一句话读法总结

> 先用「映射表」定位自己的训练场景 → 再精读对应框架的技术细节 → 最后用「趋势」校验判断是否前瞻。

---

## 结论摘要

1. **训练场景决定框架选型**：大模型训练按阶段分为预训练、监督微调（SFT）、后训练/RLHF 三大场景，不同场景的主力框架差异明显，无单一框架能最优覆盖所有场景。
2. **预训练首选 Megatron-LM + DeepSpeed 组合**：面向千亿参数以上的极限规模训练，Megatron-LM 的 4D 并行（TP/PP/DP/CP）配合 DeepSpeed ZeRO-3 是当前工业界标配。
3. **SFT 赛道 LLaMA-Factory 与 Unsloth 领跑**：LLaMA-Factory 以易用性和中文生态取胜，Unsloth 以极致速度和低显存著称，两者均支持 100+ 主流模型。
4. **RLHF/后训练方向 verl 与 OpenRLHF 并立**：verl（字节跳动）主打工业级部署和 FSDP2 深度优化；OpenRLHF（Ray + vLLM）主打学术研究和算法灵活性。
5. **国产化场景 MS-SWIFT 是唯一深度适配昇腾 NPU 的全栈框架**，同时支持 500+ 文本模型和 200+ 多模态模型。

---

## 一、主流框架全景

当前大模型训练框架按功能定位分为三层：

```
┌─────────────────────────────────────────────────┐
│           基础分布式层（预训练 / 超大规模）           │
│   Megatron-LM · DeepSpeed · PyTorch FSDP2        │
│   TorchTitan · Nanotron                          │
├─────────────────────────────────────────────────┤
│              微调层（SFT / LoRA / 多模态）          │
│   LLaMA-Factory · Axolotl · Unsloth              │
│   Torchtune · MS-SWIFT · HuggingFace TRL         │
├─────────────────────────────────────────────────┤
│         后训练层（RLHF / GRPO / DPO / PPO）        │
│   verl · OpenRLHF · NeMo RL · DeepSpeed-Chat     │
└─────────────────────────────────────────────────┘
```

---

## 二、各框架核心特性

### 2.1 预训练 / 基础分布式框架

#### Megatron-LM（NVIDIA）
- **定位**：极限规模预训练参考实现，行业标杆
- **核心技术**：4D 并行（Tensor Parallelism / Pipeline Parallelism / Data Parallelism / Context Parallelism），支持 1M+ token 长上下文训练
- **新特性（2025）**：Megatron Core（MCore）模块化分布式原语；FP8 原生训练（Hopper/Blackwell 架构）；Context Parallelism 支持超长序列分布式 Attention
- **适配场景**：百亿至万亿参数预训练、MoE 架构训练、多模态预训练
- **社区**：GitHub 15,908 stars，270 贡献者

#### DeepSpeed（Microsoft）
- **定位**：显存优化核心框架，搭配其他框架使用
- **核心技术**：ZeRO（Zero Redundancy Optimizer）三级优化——ZeRO-1/2 优化 optimizer states/gradients，ZeRO-3 全参数分片；ZeRO-Infinity 支持 CPU/NVMe offload
- **新特性（2025）**：DeepSpeed-MoE 深度优化 MoE all-to-all 通信（支持 Qwen3、DeepSeek-V3）；ZeRO-3 显存降低 40%
- **适配场景**：10B+ 参数显存受限训练、MoE 训练、RLHF（DeepSpeed-Chat）
- **关键数据**：相比无优化方案，ZeRO-3 可使 32B 模型单卡微调成为可能

#### PyTorch FSDP2
- **定位**：PyTorch 原生分片并行，轻量级分布式训练
- **核心技术**：全参数分片数据并行，与 PyTorch 生态无缝集成
- **适配场景**：10B 以下模型、高带宽 NVLink 环境
- **性能特点**："10B 规则"——模型低于 10B 或带宽充足时，FSDP2 比 DeepSpeed ZeRO-3 快最高 5 倍；梯度同步延迟低至 1.2ms（verl FSDP2 实现）
- **局限**：显存 offload 能力不及 DeepSpeed ZeRO-3，大规模模型时受限

#### TorchTitan（Meta）
- **定位**：PyTorch 原生分布式训练系统，整合最新技术的研究平台
- **核心技术**：模块化 4D 并行、弹性扩展、Float8 训练
- **适配场景**：学术研究、模型架构探索

#### Nanotron（Hugging Face）
- **定位**：极简主义研究框架
- **适配场景**：需要快速迭代模型架构的研究人员

---

### 2.2 微调框架（SFT / LoRA / 多模态）

#### LLaMA-Factory
- **定位**：模块化低代码微调平台，中文生态最完善
- **支持范围**：100+ 主流模型，15+ 训练算法（PPO / DPO / ORPO 等），LoRA / QLoRA / 全参微调
- **亮点**：Web UI 可视化训练、QLoRA 使 70B 模型训练门槛降至 24GB（4bit）、60+ 企业生产落地案例
- **适配场景**：快速 SFT 微调、RLHF 对齐、可视化需求

#### Axolotl
- **定位**：社区驱动、高度灵活的开源微调框架
- **新特性（2025）**：ND Parallelism（CP + TP + FSDP 组合）、FP8 微调、QAT 量化感知训练、Reward Modelling、GRPO 支持、多模态微调
- **适配场景**：需要高度定制化配置的研究团队

#### Unsloth
- **定位**：速度与显存极致优化
- **核心技术**：OpenAI Triton 重写核心计算（无精度损失）、LoRA/QLoRA 专项加速
- **性能数据**：相比标准训练，速度提升 2x，显存减少 50-70%
- **适配场景**：单机单卡资源受限场景、快速 LoRA 微调

#### MS-SWIFT（阿里 ModelScope）
- **定位**：国产化全栈适配方案
- **支持范围**：500+ 文本模型、200+ 多模态模型
- **亮点**：深度兼容华为昇腾 NPU 和阿里云百炼平台、AWQ/GPTQ 量化、70B 模型 4bit 训练仅需 48GB 显存
- **训练算法**：DPO / GRPO / PPO 等 10+ 算法
- **适配场景**：国产化部署、多模态 Agent 训练、昇腾 NPU 环境

#### Torchtune
- **定位**：PyTorch 官方微调框架
- **核心技术**：TorchCompile 加速、量化感知训练（QAT）、Activation Offloading
- **适配场景**：PyTorch 深度用户、RLHF 实验

---

### 2.3 后训练框架（RLHF / PPO / GRPO / DPO）

#### verl（字节跳动）
- **定位**：工业级后训练框架，FSDP2 深度优化
- **架构**：HybridFlow，训练引擎与推理引擎解耦
- **支持算法**：DAPO / VAPO / PRIME / GRPO / PPO 等 15+ 算法
- **性能**：GPU 利用率达 85%，FSDP2 梯度同步延迟 1.2ms
- **生态**：AMD Instinct MI300 深度优化
- **适配场景**：工业级部署、大规模后训练、AMD GPU 用户

#### OpenRLHF
- **定位**：学术研究首选，易用性与可扩展性兼顾
- **架构**：Ray + vLLM + DeepSpeed ZeRO-3
- **支持算法**：PPO / REINFORCE++ / GRPO 等 10+ 算法
- **性能数据**：相比同类框架速度提升 1.22x-1.68x；vLLM 加速样本生成吞吐量提升 2.3x
- **关键优势**：代码量少（对比 DeepSpeed-Chat），推理阶段效率高（占 RLHF 总时长 90%+）
- **适配场景**：学术 RLHF 研究、SOTA 复现

#### NeMo RL（NVIDIA）
- **定位**：NVIDIA 全栈后训练解决方案
- **架构**：与 Megatron-Core 深度集成，支持 DTensor / FSDP2 / TP / SP / CP
- **推理引擎**：vLLM 或 Megatron Native Inference
- **适配场景**：NVIDIA 全栈用户、超大规模工业后训练

---

## 三、框架 × 训练场景映射表

| 训练场景 | 首选框架 | 备选框架 | 核心需求 |
|---------|---------|---------|---------|
| **大规模预训练（100B+）** | Megatron-LM + DeepSpeed | NeMo | 4D 并行、FP8、极致吞吐 |
| **中小规模预训练（<10B）** | PyTorch FSDP2 / TorchTitan | Nanotron | 轻量分布式、快速迭代 |
| **MoE 架构训练** | Megatron-LM + DeepSpeed-MoE | NeMo RL | all-to-all 通信优化 |
| **全参 SFT 微调** | LLaMA-Factory / Axolotl | Torchtune | 易用性、算法覆盖 |
| **LoRA / QLoRA 微调** | Unsloth + LLaMA-Factory | Axolotl / SWIFT | 显存效率、速度 |
| **多模态训练** | MS-SWIFT | Axolotl / LLaMA-Factory | 视觉-语言模型支持 |
| **RLHF / PPO 对齐** | verl / OpenRLHF | NeMo RL / TRL | 推理-训练解耦、PPO 稳定性 |
| **GRPO / 强化学习推理** | verl / OpenRLHF | LLaMA-Factory | 无 Critic 高效训练 |
| **DPO / 偏好学习** | LLaMA-Factory / SWIFT | TRL / Axolotl | 离线偏好数据训练 |
| **国产化 / 昇腾 NPU** | MS-SWIFT | — | 昇腾生态深度适配 |
| **资源受限（单卡）** | Unsloth | LLaMA-Factory QLoRA | 极低显存占用 |
| **学术快速原型** | Nanotron / Torchtune | Axolotl | 代码简洁、易修改 |

---

## 四、生态与社区活跃度

| 框架 | GitHub Stars | 主要维护方 | 活跃度（2025） |
|------|-------------|-----------|--------------|
| Megatron-LM | ~15,900 | NVIDIA | 高，持续更新 MCore |
| DeepSpeed | ~35,000+ | Microsoft | 高，MoE 重点更新 |
| LLaMA-Factory | ~35,000+ | 独立开发者 | 极高，中文社区核心 |
| Unsloth | ~25,000+ | 独立团队 | 高，每周有新优化 |
| Axolotl | ~8,000+ | 社区驱动 | 中高，功能迭代活跃 |
| MS-SWIFT | ~5,000+ | 阿里 ModelScope | 高，多模态重点 |
| verl | ~8,000+ | 字节跳动 | 高，DAPO/VAPO 首发 |
| OpenRLHF | ~5,000+ | 社区 | 高，论文引用广 |
| TorchTitan | ~2,000+ | Meta | 中，研究导向 |

---

## 五、2026 年趋势展望

1. **GRPO 取代 PPO 趋势明显**：DeepSeek-R1 带火 GRPO，verl / OpenRLHF / LLaMA-Factory 均在 2025 年完成支持，无 Critic 的后训练成为新范式
2. **FP8 训练普及**：Megatron-LM 与 Axolotl 均在 2025 年加入 FP8 原生支持，吞吐量提升约 2 倍
3. **异构计算适配提速**：MS-SWIFT 的昇腾适配、verl 的 AMD MI300 优化、FSDP2 的跨硬件统一接口，异构训练生态快速成熟
4. **框架算法互补加速**：OpenRLHF 计划集成 verl 的 DAPO 算法，框架边界开始模糊化
5. **超长上下文训练**：Context Parallelism（1M+ token）在 Megatron-LM 和 Axolotl 中均已落地，支持长链条推理模型训练

---

## 六、调研局限性

- **性能数据**：部分 benchmark 数据来源于框架官方报告，存在场景偏向，实际性能受硬件、模型架构、数据规模影响
- **未覆盖**：Colossal-AI、Pai-Megatron（阿里 PAI）等框架信息不足；国内私有化部署框架信息有限
- **动态更新**：2025-2026 年框架迭代极快，部分 API 和功能可能已有新版本

---

## 参考来源

1. [The 2026 AI Engineering Stack: A Definitive Guide to LLM Frameworks](https://www.tiptinker.com/llm-frameworks/)
2. [DeepSpeed vs FSDP: Choosing Frameworks Based on Model Size](https://aionda.blog/en/posts/deepspeed-vs-fsdp-training-strategy)
3. [大语言模型 RLHF 训练框架全景解析：OpenRLHF、verl、LLaMA-Factory 与 SWIFT 深度对比](https://www.vps345.com/10428.html)
4. [Comparing LLM Fine-Tuning Frameworks: Axolotl, Unsloth, and Torchtune in 2025](https://blog.spheron.network/comparing-llm-fine-tuning-frameworks-axolotl-unsloth-and-torchtune-in-2025)
5. [OpenRLHF: An Easy-to-use, Scalable and High-performance RLHF Framework](https://arxiv.org/html/2501.03262v4)
6. [NVIDIA/Megatron-LM GitHub](https://github.com/NVIDIA/Megatron-LM/)
7. [2025 十大主流 & 新锐 LLM 训练框架多维度对比分析](https://adg.csdn.net/696f4d8d437a6b403369f550.html)
8. [Open Source RL Libraries for LLMs | Anyscale](https://anyscale.com/blog/open-source-rl-libraries-for-llms)
