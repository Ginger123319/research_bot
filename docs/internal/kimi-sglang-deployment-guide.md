# Kimi K25 SGLang 部署指导文件

> 记录日期：2026-05-18  
> 目标：将 Kimi K25（MoE + VLM）使用 SGLang 在 3 节点 L20 集群上部署并优化推理性能

---

## 一、硬件与模型基本情况

### 硬件

| 项 | 值 |
|---|---|
| 节点数 | 3 |
| 每节点 GPU | 8 × NVIDIA L20 |
| 单卡显存 | 46GB |
| 总显存 | **1,104GB** |
| 节点内互联 | PCIe Gen4（无 NVLink）|
| 节点间互联 | **Ethernet**（非 InfiniBand）|

**关键限制**：L20 没有 NVLink，节点间是 Ethernet。SGLang 文档明确指出 PCIe 集群做 Tensor Parallel 性能比 NVLink 差约 10x，Ethernet 跨节点 all-reduce 会进一步放大延迟。这是本方案最大的性能天花板。

### 模型

| 项 | 值 |
|---|---|
| 模型路径 | `/model/liuxinyang/train/kimi/kimi-prod-8nodes-all/checkpoint-4276-merged` |
| 外层架构 | `KimiK25ForConditionalGeneration`（自定义，带 Vision Tower）|
| 文本骨干 | `DeepseekV3ForCausalLM`（SGLang 原生支持）|
| MoE 结构 | 61 层，每层 384 个 routed expert，每 token 激活 8 个，1 个 shared expert |
| 注意力 | MLA（`kv_lora_rank=512`, `q_lora_rank=1536`）|
| 上下文长度 | 最大 262,144 token（YaRN scaling）|
| 量化方案 | `compressed-tensors`，int4 group_size=32 |
| 量化范围 | **仅 routed expert 线性层**；attention / shared expert / LM head / vision tower 均保留 bf16 |

### 显存估算

| 部分 | 精度 | 估算大小 |
|---|---|---|
| Routed expert 权重（60层×384专家）| int4 | ~500GB |
| Attention + shared expert + dense 层 | bf16 | ~30GB |
| Vision tower + projector | bf16 | ~7GB |
| LM head | bf16 | ~2GB |
| **模型权重合计** | | **~540GB** |
| KV cache 可用空间 | | **~560GB** |

单节点 8 卡 = 368GB，**单机无法加载**，必须 3 节点部署。

### LoRA 信息

训练时使用 PEFT LoRA，`target_modules: "all-linear"`（覆盖全部线性层，包含 int4 量化的 expert 层），rank=32，alpha=32。

单个 LoRA adapter 估算大小约 **45-55GB**（bf16），主要来自 23,040 个 routed expert 的 A/B 矩阵。

当前已有 **merged checkpoint**（LoRA 已合并进 base 权重），是当前最稳妥的部署路径。

---

## 二、部署计划

### P0：多节点环境验证

**目标**：确认 3 节点 SGLang 集群本身能跑通，排除环境问题。

用官方支持的模型（如 Llama 3.1 405B）验证，而非直接上 Kimi 模型。

```bash
# 节点 0（主节点，替换 <node0_ip>）
sglang serve \
    --model-path meta-llama/Meta-Llama-3.1-405B-Instruct \
    --tp-size 24 \
    --dist-init-addr <node0_ip>:20000 \
    --nnodes 3 --node-rank 0

# 节点 1
sglang serve \
    --model-path meta-llama/Meta-Llama-3.1-405B-Instruct \
    --tp-size 24 \
    --dist-init-addr <node0_ip>:20000 \
    --nnodes 3 --node-rank 1

# 节点 2
sglang serve \
    --model-path meta-llama/Meta-Llama-3.1-405B-Instruct \
    --tp-size 24 \
    --dist-init-addr <node0_ip>:20000 \
    --nnodes 3 --node-rank 2
```

必须配置的 NCCL 环境变量（Ethernet 集群）：

```bash
export NCCL_SOCKET_IFNAME=<网卡名，如 eth0 或 bond0>
export NCCL_DEBUG=INFO          # 调试阶段打开，确认连接正常后关闭
export NCCL_IB_DISABLE=1        # 无 InfiniBand 时必须设置
```

**验收**：`curl http://<node0_ip>:30000/health` 返回正常，发送一条推理请求能拿到输出。

---

### P1：Kimi 模型加载验证

**目标**：确认 SGLang 能识别 `KimiK25` 自定义架构并正确加载 `compressed-tensors` 量化。

```bash
# 节点 0
sglang serve \
    --model-path /model/liuxinyang/train/kimi/kimi-prod-8nodes-all/checkpoint-4276-merged \
    --trust-remote-code \
    --tp-size 24 \
    --dist-init-addr <node0_ip>:20000 \
    --nnodes 3 --node-rank 0
```

启动日志关注点：
1. 量化是否被识别：日志应出现 `compressed-tensors` 或相关内核名称
2. 架构是否加载成功：如报 `KeyError` / `AttributeError` / `model_type not found`，说明 SGLang 不认识 `kimi_k25`，需要适配
3. 权重加载完成日志（`Model loaded`）

**验收**：模型启动不报错退出，发送文本请求输出不乱码。

---

### P2：基础推理质量验收

**目标**：输出质量与 merge 前 baseline 对比基本一致。

```python
import requests

response = requests.post("http://<node0_ip>:30000/generate", json={
    "text": "用一句话解释什么是 MoE 模型",
    "sampling_params": {"max_new_tokens": 256, "temperature": 0}
})
print(response.json()["text"])
```

如有条件，跑一个小规模评估集（如 50-100 条），对比 merged 权重和原始模型输出的差异。

---

### P3：性能摸底

**目标**：测出当前架构下的性能基线，定位瓶颈。

使用 SGLang 内置 benchmark 工具：

```bash
python3 -m sglang.bench_serving \
    --backend sglang \
    --host <node0_ip> --port 30000 \
    --num-prompts 100 \
    --input-len 512 --output-len 256 \
    --request-rate 4
```

关注指标：
- **TTFT**（Time to First Token）：反映 prefill 速度
- **TPS**（Tokens Per Second）：反映 decode 吞吐
- **GPU 利用率** vs **网络利用率**：判断瓶颈

**Ethernet 跨节点的性能预期**：

Ethernet（100GbE）跨节点 all-reduce 带宽约 12 GB/s（双向），远低于 IB 的 200-400 GB/s。TP=24 跨 3 节点时，每次 all-reduce 的通信量 ∝ hidden_size × batch_size，对于 hidden_size=7168，**网络几乎必然成为瓶颈**。

---

### P4：性能优化

根据 P3 的 profiling 结果，选择方向：

**方向 A：Chunked Prefill（优先尝试）**

减少单次 prefill 的计算量，降低 TTFT，提高 decode 阶段对 GPU 的利用率：

```bash
sglang serve ... --chunked-prefill-size 2048
```

**方向 B：Pipeline Parallel + Tensor Parallel 混合（跨节点通信优化）**

PP 将模型按层切分到不同节点，跨节点只传 activation（point-to-point），不做 all-reduce，对 Ethernet 集群更友好。但 SGLang 的 PP 支持成熟度需要单独确认（当前文档里 TP 是主推路径，PP 支持有限）。

目标组合：PP=3（每节点一个 pipeline stage）× TP=8（节点内 8 卡 TP）：

```bash
sglang serve ... --tp-size 8 --pp-size 3
```

> 执行前需确认 SGLang 当前版本是否支持 PP，以及 `--pp-size` 参数。

**方向 C：调整 KV cache 分配**

如果 decode 阶段 GPU 显存利用率低，可增大 KV cache 比例：

```bash
sglang serve ... --mem-fraction-static 0.85
```

---

### P5：Separate LoRA 部署（按需）

**前提**：P0-P3 全部稳定，且有明确的多 LoRA 并发服务需求。

**当前已知风险**：
- `target_modules: "all-linear"` 覆盖了 int4 量化的 routed expert 层
- SGLang 的 compressed-tensors 量化路径是否支持 LoRA forward，文档里没有明确案例
- Marlin+LoRA 的 PR（#21858）针对 Marlin 后端，与 compressed-tensors 是不同的量化内核路径

**验证命令**（能跑才推进）：

```bash
sglang serve \
    --model-path <base_model_path> \
    --trust-remote-code \
    --enable-lora \
    --lora-paths lora0=<lora_adapter_path> \
    --max-loras-per-batch 2 \
    --max-lora-rank 32 \
    --tp-size 24 \
    --dist-init-addr <node0_ip>:20000 \
    --nnodes 3 --node-rank 0
```

如果不支持，备选方案：
1. 继续用 merged 权重（已验证可行）
2. 对每个 LoRA 做一次 merge，分别部署为独立实例，用上层路由区分

---

## 三、需要补充学习的任务

| 优先级 | 任务 | 用途 | 入口 |
|---|---|---|---|
| P0 必须 | SGLang 多节点启动参数 + NCCL Ethernet 配置 | 节点联通 | SGLang [multi-node 文档](https://sgl-project.github.io/references/multi_node_deployment/multi_node.html) |
| P1 必须 | SGLang `compressed-tensors` 量化内核路径，L20（SM89）兼容性 | 确认模型能加载 | `sglang/srt/layers/quantization/compressed_tensor.py` |
| P1 必须 | SGLang `--trust-remote-code` 自定义模型加载机制 | 处理 `KimiK25` 架构 | SGLang 源码模型注册表 |
| P3-P4 | SGLang chunked prefill 原理与参数调优 | 提升吞吐 | SGLang server arguments 文档 |
| P4 按需 | SGLang Pipeline Parallel 当前支持状态 | Ethernet 环境下降低跨节点通信开销 | SGLang GitHub issues / changelog |
| P5 按需 | compressed-tensors + LoRA 内核兼容性 | separate LoRA 部署 | SGLang issue #9449 + PR #21858 |

---

## 四、已知风险汇总

| 风险 | 等级 | 描述 |
|---|---|---|
| 自定义架构不被 SGLang 识别 | 高 | `KimiK25ForConditionalGeneration` 非 SGLang 原生支持，`--trust-remote-code` 不一定够 |
| Ethernet 跨节点 all-reduce 成瓶颈 | 高 | TP=24 每层都有跨节点通信，Ethernet 带宽可能使 TPS 很低 |
| compressed-tensors + LoRA 不兼容 | 中 | separate LoRA 路线的技术依据不足，可能需要等上游或自行适配 |
| PP 支持不成熟 | 中 | P4 优化的备选方案依赖 SGLang PP 支持，需要单独确认 |
| L20 特定量化内核缺失 | 低 | Marlin 等内核在 SM89 上通常支持，compressed-tensors 需要验证 |
