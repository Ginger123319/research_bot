# AI-Infra 工程师成长路线图：以 Profiling + 优化为核心能力

> 写于：2026-05-22  
> 背景：AI-Infra 工程师，有推理性能优化经验，正在开展训练框架开发工作  
> 硬件环境：8 台 H200（64 卡），服务于 235B MoE + Kimi-K2.6（~1.2T MoE）LoRA SFT 训练

---

## 核心定位

**硬件固定，模型通用，以 profiling + 优化方法论为护城河。**

```
推理性能优化（已有）
        +
训练框架开发（在建）
        ↓
目标：能快速 profile 任意 AI 训练/推理任务，定位瓶颈，解决它
```

框架会变，方法论不变。专精某个框架的工程师是可替换的；能在任何框架上快速定位瓶颈的工程师是稀缺的。

---

## 一、profiling + 优化方法论

### 1.1 六步完整分析链（每次优化必须走完）

```
1. 测量   → 拿到量化数字（MFU、step time、tokens/sec）
2. Profile → 分解时间占比（计算 / 通信 / bubble / IO）
3. 定位   → 找到最大的单一瓶颈（不猜）
4. 假设   → 说出"改 X 会因为 Y 原因使 Z 提升"
5. 改动   → 只改一个变量
6. 验证   → 记录 before/after，解释为什么符合或不符合预期
```

**示例记录格式：**

```
优化项：ZBV 流水线替换 1F1B
Before：step time = 1850ms，MFU = 27%，PP bubble 占 18%
After： step time = 1530ms，MFU = 33%，PP bubble 降至 2%
原因：ZBV 将 backward 拆为 B pass（input grad）和 W pass（weight grad），
      W pass 可提前调度下一 microbatch，消除 PP 等待时间
```

### 1.2 AI 系统的四层分析框架

```
Layer 4：应用层     MFU、tokens/sec、step time
              ↑ 症状在这里出现
Layer 3：框架层     TP comm、PP bubble、EP A2A、AC 开销
              ↑ 通常瓶颈在这里
Layer 2：Kernel层   SM 利用率、memory bandwidth、Arithmetic Intensity
              ↑ 深层瓶颈在这里
Layer 1：硬件层     NVLink 带宽、IB 带宽、HBM 带宽
              ↑ 瓶颈的物理上限在这里
```

**定位顺序：从 Layer 4 往下钻，找到第一个"实测值 << 理论上限"的层。**

### 1.3 Roofline 模型：判断 compute-bound vs memory-bound

H200 BF16 关键参数：
```
计算上限：1979 TFLOPS
内存带宽：~4.8 TB/s
Ridge point：1979e12 / 4.8e12 ≈ 412 FLOP/Byte

Arithmetic Intensity（AI）= FLOPs / Bytes_accessed
  AI > 412 → compute-bound（提速方向：更好的算法、更高精度利用率）
  AI < 412 → memory-bound（提速方向：kernel fusion、减少 HBM 读写）
```

**典型算子的 AI：**

| 算子 | 典型 AI | 类型 |
|------|---------|------|
| Large GEMM（M=N=K=4096） | ~1000 | Compute-bound |
| LayerNorm | ~10 | Memory-bound |
| Attention（短序列） | ~50 | Memory-bound |
| Attention（长序列，FlashAttention） | ~300 | 接近 Ridge |
| All-Reduce | <10 | 带宽受限 |

### 1.4 Nsight Systems Timeline 解读指南

**五个关键 Track：**

```
CUDA HW（SM 活跃度）
  → 接近 100%：GPU 在全力计算
  → 骤降至 0：在等通信 / bubble / CPU 调度

CUDA API（kernel launch）
  → 大量小间隔：kernel launch overhead，考虑 CUDAGraph

NCCL
  → ncclAllToAll：EP expert dispatch
  → ncclAllGather/ReduceScatter：TP 通信
  → ncclAllReduce：DP gradient sync

NVTX（框架标注）
  → forward / backward / optimizer_step 的时间边界

Memory
  → 频繁 cudaMalloc：动态分配碎片，影响性能
```

**常见"空白"的根因：**

| 现象 | 根因 | 解决方向 |
|------|------|---------|
| SM 降低 + NCCL 活跃 | 在等通信（TP/EP/DP） | 通信 overlap |
| SM 降低 + 无 NCCL | PP bubble 或 CPU 调度延迟 | ZBV / CUDAGraph |
| 大量小 kernel + 间隔 | kernel launch overhead | torch.compile / CUDAGraph |
| NCCL 时间长但 SM 不低 | 通信和计算未重叠 | 检查 overlap 配置 |

---

## 二、工作中的执行计划

### 阶段 0（第 1-2 周）：建立 profiling 基线

**任务：在 8 台 H200 上，跑一次完整 LoRA SFT，产出第一张时间分布图。**

```bash
# 方法一：看 Megatron 训练日志（最快）
# 找这行：TFLOPs: XXX.X
# MFU = TFLOPs / (64 × 1979)

# 方法二：PyTorch Profiler
from torch.profiler import profile, ProfilerActivity, schedule
with profile(
    activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA],
    schedule=schedule(wait=2, warmup=2, active=3),
    on_trace_ready=torch.profiler.tensorboard_trace_handler('./prof'),
) as prof:
    for step in range(7):
        train_one_step()
        prof.step()
```

**交付物：**
```
模型    | 并行配置           | MFU  | 计算% | TP通信% | EP A2A% | PP bubble%
235B   | TP8 PP2 EP4 DP2   | ??%  | ??%  | ??%    | ??%    | ??%
1.2T   | TP8 PP4 EP8 DP1   | ??%  | ??%  | ??%    | ??%    | ??%
```

这张表是后续所有优化的起点，填完之前不要启动任何优化。

### 阶段 1（第 3-8 周）：配置级优化，验证每项收益

按 profile 结果决定顺序，每项优化走完完整六步分析链：

| 优化项 | Megatron 参数 | 预期收益 | 工作量 |
|--------|--------------|---------|--------|
| ZBV 流水线 | `--zero-bubble-v-schedule` | PP=4 时 MFU +20%+ | 1-2 周 |
| TP comm overlap | `--tp-comm-overlap` | MFU +5-10% | 2 天验证 |
| EP A2A overlap | `--overlap-moe-expert-parallel-comm` | MFU +5-15% | 2 天验证 |
| FP8 frozen 权重 | `--fp8-format hybrid` | 显存省半，减少 AC 开销 | 1 周 |
| Selective AC | `--recompute-granularity selective` | 显存 -40%，计算 +5% | 半天 |

### 阶段 2（第 9-16 周）：内部系统集成

- 内部数据格式 → Megatron IndexedDataset 格式的转换器
- Checkpoint 存储对接内部对象存储
- 训练指标上报内部监控系统
- 自动化 MFU benchmark 脚本（每次改动自动出 before/after 报告）

### 阶段 3（第 4-6 个月）：针对性深度优化

由 profile 数据驱动，预期目标：

```
目标：在 8 台 H200 上，235B MoE 和 Kimi-K2.6 LoRA SFT 的 MFU
      均比 ms-swift 当前基线提升 20%+，有可重复的 benchmark 数据
```

候选项（根据 profile 结果选最大瓶颈）：
- MoE EP MegaKernel 融合（UniEP 方向，dispatch + GroupGEMM + combine）
- 拓扑感知 All-to-All（intra-node NVLink + inter-node IB 两阶段）
- FlashAttention-3 集成（H200 Hopper 架构，FA-3 比 FA-2 快约 1.5×）

---

## 三、工作外的 12 个月学习路线

### 阶段一（第 1-3 个月）：搞懂 GPU 在做什么

**目标**：看到一个 kernel 运行慢，能说出是 compute-bound 还是 memory-bound，并知道为什么。

**月 1：GPU 架构基础**
- 教材：《Programming Massively Parallel Processors》第 1-5 章
- 重点：内存层次（寄存器/L1/L2/HBM）、warp 调度、shared memory bank conflict
- 动手：写一个 naive 矩阵乘（CUDA C），测量和理论峰值的差距
- 每章配合书中练习题，不要只读不写

**月 2：Roofline 模型实操**
- 对你们训练中实际用到的算子计算 Arithmetic Intensity
  - GEMM（不同 shape）
  - LayerNorm
  - Attention（不同 seq_len）
- 用 Nsight Compute 验证：算子实测性能和 Roofline 预测的上限对比
- 目标：对任意算子，能在 5 分钟内算出它的理论上限

**月 3：Triton 实战**
- 用 Triton 写 fused layer norm（LayerNorm + Dropout 合并）
- 用 Triton 写 softmax（验证 online softmax 的实现）
- 参考：Triton 官方 tutorial（triton-lang.org），直接跟着做

**阶段一验收标准**：拿到一份 Nsight Compute 报告，能在 10 分钟内解释：
- 这个 kernel 的 Arithmetic Intensity 是多少
- 它是 compute-bound 还是 memory-bound
- 理论上还能快多少，主要限制在哪里

---

### 阶段二（第 4-6 个月）：Nsight Systems 深度分析

**目标**：对任意训练 step，能在 30 分钟内给出瓶颈定位报告。

**月 4：Nsight Systems 工具掌握**
- 安装并熟悉 UI：timeline view、statistics view、NVTX 标注
- 实操：对你们当前的训练 job 跑一次完整 profile
- 练习：逐段解释每个 >1ms 的空白，写成文字

**月 5：分布式通信 profile**
- 重点看 NCCL 的各种 collective 在 timeline 上的样子
- 学会区分：TP AllGather / EP AllToAll / DP AllReduce 各自的特征
- 对比：有 overlap 和没有 overlap 时，timeline 的形态有何不同

**月 6：端到端分析实战**
- 选你们框架里一个已知有问题的场景（比如 MFU 只有 25% 的配置）
- 完整走六步分析链，输出一页分析报告
- 找同事 review，验证分析是否正确

**阶段二验收标准**：对一个陌生的训练 profile，30 分钟内给出：
- 时间分布（计算/TP通信/EP A2A/PP bubble 各占比）
- 最大瓶颈是什么
- 建议的优化方向

---

### 阶段三（第 7-12 个月）：读懂关键论文

**目标**：读一篇论文，能说出"他们的问题是什么、为什么这样设计、适不适用我们的场景"。

**必读论文（按优先级）：**

| 论文 | 核心问题 | 读完能回答什么 |
|------|---------|--------------|
| FlashAttention-2（Dao, 2023） | attention 为什么 memory-bound，怎么解决 | tiling 的 IO 复杂度推导；online softmax 怎么工作 |
| Megatron-LM（Narayanan, 2021） | TP/PP/SP 的设计决策 | sequence parallel 为什么必要；1F1B bubble rate 公式 |
| ZeRO（Rajbhandari, 2020） | 显存如何切分 | ZeRO-3 的显存公式；为什么通信量是 1.5× |
| ZBV 论文（Sea AI Lab, 2023） | 零 bubble 怎么实现 | B/W pass 分离的原理；ZBV 的 bubble rate 公式 |
| DeepSeek-V3 技术报告（2025） | MLA + MoE 架构设计 | 你们用的模型的第一手设计逻辑 |

**读法（每篇）：**
1. 读之前：写 3 个问题（你想从这篇论文得到什么答案）
2. 读摘要 + 引言 + 方法章节（不要全读）
3. 读完：回答这 3 个问题，写一段"如果我来设计，会怎么做"
4. 对比：他们的设计和你的想法有什么不同，为什么他们这样做

**选读（拓宽视野，每季度 1-2 篇）：**
- MLSys 2025/2026 最佳论文列表
- 当前使用技术的最新改进（如 FlashAttention-3、UniEP 等）

---

## 四、每周时间投入参考

```
工作日：1 小时/天（早上或下班后）
周末：  2-3 小时（集中学习或写代码）
合计：  约 7-8 小时/周
```

**优先级原则**：
- 工作中的 profiling 任务 > 工作外的学习（实战最有效）
- 卡住时先看工具文档，不要看解读博客
- 每学一个概念，找一个实际训练场景验证一次

---

## 五、三年后的目标画像

```
现在（2026）：AI-Infra 工程师，训练+推理双侧经验
1 年后（2027）：能端到端 profile 任意 AI 任务，出具有说服力的分析报告；
                框架在 8×H200 上对所有 MoE 模型 MFU 超越 ms-swift 20%+
2 年后（2028）：对 GPU kernel 级别有实操经验（写过 Triton kernel）；
                能快速 onboard 到任何新模型架构并诊断其训练效率
3 年后（2029）：ML Systems Engineer；能既设计训练/推理系统，
                又能参与模型方向的技术决策
```

**出口方向：**
- 头部公司 ML Systems 团队（字节 AML / 百度 / 阿里通义基础设施）
- AI 创业公司早期基础设施工程师
- MLSys 方向研究（基于实际工程经验投稿 MLSys/OSDI/SOSP）

---

## 六、一个持续的警惕

> **避免变成"维护框架"的人，而不是"推动能力建设"的人。**

防止的方法：
- 持续关注算法团队在做什么，让框架工作和公司最重要的模型建设直接相关
- 主动去问"你们的训练慢在哪里"，而不是等他们来找你
- 每隔 3 个月问自己："我过去 3 个月的工作，让公司的模型能力好了多少？"

框架是手段。让框架帮公司训出更好的模型，才是目的。
