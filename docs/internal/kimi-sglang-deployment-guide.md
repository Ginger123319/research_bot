# Kimi K25 SGLang 部署指导文件

> 记录日期：2026-05-18（更新：2026-05-20）  
> 目标：将 Kimi K25/K2.6（MoE + VLM）使用 SGLang 在集群上部署；并与 vLLM INT4+LoRA 路线对照  
> SGLang 版本：**v0.5.12**（v0.5.11 明确支持 Kimi-K2 LoRA，v0.5.12 加入 Virtual Experts 优化）

---

## vLLM 实验进展交叉引用（2026-05-20）

本轮在 **vLLM** 上推进 Kimi-K2.6 INT4 base + 独立 LoRA，详细记录见 [`vllm-moe-lora-deployment-guide.md`](./vllm-moe-lora-deployment-guide.md)。摘要：

| 项目 | 状态 |
|------|------|
| DeepSeek-V2-Lite + LoRA（L20 容器，cu130 镜像） | ✅ vLLM MoE LoRA 路径已验证 |
| Kimi-K2.6 INT4 + LoRA（H20 8 卡 K8s） | ❌ Driver 570 下 cu130/cu129 均未跑通 |
| bf16 全量 merge ~2TB | ❌ 不可部署；坚持 INT4 base + LoRA 或 INT4 merged ~600GB |
| 测试 LoRA（Tinker→PEFT 77GB） | ✅ 转换完成；serving 未验证 |

**镜像切换（2026-05-20）**：`cu130`（L20 DeepSeek ✅，H20 Kimi driver too old）→ `x86_64-ubuntu2404`（cu129，Marlin PTX 失败）→ Harbor `reg.xxwolo.com/master/vllm:v0.19.0-x86_64-ubuntu2404`。

**若 vLLM 短期无法解决驱动/PTX**：本文件 SGLang 路线为备选；官方文档 [Kimi-K2.6 deploy_guidance](https://huggingface.co/moonshotai/Kimi-K2.6/blob/main/docs/deploy_guidance.md)、[SGLang cookbook](https://cookbook.sglang.io/autoregressive/Moonshotai/Kimi-K2.6)。

**H20 单机（8×96GB）与 L20 三节点（8×46GB×3）差异**：内网 INT4 merged checkpoint 原按 3×L20 TP24 设计；H20 单机 768GB 可尝试 TP8 只加载 INT4 base（~595GB），需单独验证。

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

**业务 LoRA 路径**（算法团队产出，2026-05-22）：`/mnt/ai-llm/xingyan_v1_Kimi-k26_16384`  
> 注：路径中 `16384` = 训练时 context_length（已确认）；rank 待向算法确认；使用前需确认 adapter 格式（PEFT 可直接加载，Tinker 格式需先 `build_lora_adapter` 转换）。

---

## 二、部署计划

### P0：环境安装

```bash
pip install sglang==0.5.12
python -c "import sglang; print(sglang.__version__)"  # 确认输出 0.5.12
```

NCCL 环境变量（Ethernet 集群，只有一张数据网卡 eth0，无需配 NCCL_SOCKET_IFNAME）：

```bash
export NCCL_IB_DISABLE=1    # 无 InfiniBand
export NCCL_DEBUG=INFO      # 调试阶段开启，确认网卡选择正确后关闭
```

启动后用 `NCCL_DEBUG=INFO` 日志确认 NCCL 选中了 `eth0`（172.21.x.x 网段）而非 docker0。

---

### T1：小模型验证 MoE LoRA 路径（单节点，2 张 L20）

**目的**：在权重未到位前，用公开小模型验证 SGLang v0.5.12 的 MoE LoRA 全流程是否正常。

**模型**：`deepseek-ai/DeepSeek-V2-Lite-Chat`（16B MoE，bf16 约 32GB，2 卡够用）  
**LoRA**：`wuchen01/DeepSeek-V2-Lite-Chat-All-LoRA`（PR #19711 验证过的架构）

```bash
sglang serve deepseek-ai/DeepSeek-V2-Lite-Chat \
    --tp-size 2 \
    --enable-lora \
    --lora-paths lora0=wuchen01/DeepSeek-V2-Lite-Chat-All-LoRA \
    --lora-backend triton \
    --max-lora-rank 64 \
    --max-loras-per-batch 2 \
    --disable-shared-experts-fusion \
    --disable-radix-cache \
    --mem-fraction-static 0.85 \
    --port 30000
```

验证 LoRA 生效（两条请求输出应有差异）：

```bash
# base model
curl http://localhost:30000/generate \
  -d '{"text":"介绍MoE模型","sampling_params":{"max_new_tokens":64}}'

# lora0
curl http://localhost:30000/generate \
  -d '{"text":"介绍MoE模型","lora_path":"lora0","sampling_params":{"max_new_tokens":64}}'
```

**验收**：两条输出不同，且 lora0 输出不乱码。

---

### P1：Kimi 模型加载验证（3 节点，权重到位后）

**目标**：确认 SGLang v0.5.12 能识别 `KimiK25` 架构并正确加载 `compressed-tensors` 量化。

```bash
# 节点 0（主节点，替换 <node0_ip>，当前已知为 172.21.180.13）
sglang serve \
    --model-path /model/liuxinyang/train/kimi/kimi-prod-8nodes-all/checkpoint-4276-merged \
    --trust-remote-code \
    --tp-size 24 \
    --dist-init-addr 172.21.180.13:20000 \
    --nnodes 3 --node-rank 0 \
    --port 30000

# 节点 1
sglang serve \
    --model-path /model/liuxinyang/train/kimi/kimi-prod-8nodes-all/checkpoint-4276-merged \
    --trust-remote-code \
    --tp-size 24 \
    --dist-init-addr 172.21.180.13:20000 \
    --nnodes 3 --node-rank 1

# 节点 2
sglang serve \
    --model-path /model/liuxinyang/train/kimi/kimi-prod-8nodes-all/checkpoint-4276-merged \
    --trust-remote-code \
    --tp-size 24 \
    --dist-init-addr 172.21.180.13:20000 \
    --nnodes 3 --node-rank 2
```

启动日志关注点：
1. 量化识别：日志出现 `compressed-tensors` 或相关内核名
2. 架构加载：无 `KeyError` / `model_type not found`
3. 加载完成：出现 `Model loaded` 或 `/health` 返回正常

**验收**：

```bash
curl http://172.21.180.13:30000/generate \
  -d '{"text":"用一句话解释MoE模型","sampling_params":{"max_new_tokens":64}}'
```

---

### P2：Kimi + LoRA 验证（T1 和 P1 都通过后）

**目标**：验证 Kimi 模型的 MoE LoRA 路径，确认 `compressed-tensors` + LoRA 兼容。

```bash
# 节点 0
sglang serve \
    --model-path <kimi_base_model_path> \
    --trust-remote-code \
    --tp-size 24 \
    --dist-init-addr 172.21.180.13:20000 \
    --nnodes 3 --node-rank 0 \
    --enable-lora \
    --lora-paths lora0=/mnt/ai-llm/xingyan_v1_Kimi-k26_16384 \
    --lora-backend triton \
    --max-lora-rank 32 \
    --max-loras-per-batch 2 \
    --disable-shared-experts-fusion \
    --disable-radix-cache \
    --mem-fraction-static 0.85
```

验证：

```bash
# base
curl http://172.21.180.13:30000/generate \
  -d '{"text":"测试","sampling_params":{"max_new_tokens":32}}'

# lora
curl http://172.21.180.13:30000/generate \
  -d '{"text":"测试","lora_path":"lora0","sampling_params":{"max_new_tokens":32}}'
```

**注意**：如果报错，优先看是否是 `compressed-tensors` + LoRA 不兼容。此时备选是退回 merged 权重方案（P1 路径），放弃 separate LoRA。

---

### P3：性能摸底

**目标**：获取基线性能数据，定位瓶颈。

```bash
python3 -m sglang.bench_serving \
    --backend sglang \
    --host 172.21.180.13 --port 30000 \
    --num-prompts 100 \
    --input-len 512 --output-len 256 \
    --request-rate 4
```

关注：TTFT（prefill 速度）、TPS（decode 吞吐）、GPU 利用率 vs 网络利用率。

**Ethernet 性能预期**：10-25 GB/s 跨节点带宽，TP=24 下网络大概率成瓶颈，TPS 会偏低。

---

### ⚠️ 性能对比测试的可比性陷阱（2026-05-22）

当对比两套部署（如 base-only vs base+LoRA，或两个不同系统）时，以下两种测试配置**表面等价、实际不可比**：

| | 测试 A | 测试 B |
|---|---|---|
| System prompt | 1630 tokens | 0 tokens |
| User prompt | 70 tokens | 70 tokens |
| Prefix cache | 开启 | 关闭 |
| 表面 prefill tokens | 70（1630 命中缓存） | 70 |

**为什么不可比：**

**TPOT（每输出 token 耗时）不可比**：每个 decode step，Attention 都需要从 KV cache 读取全部 context 的 K/V 向量。A 的每步要读 1630 + 70 = **1700 token 的 KV**，B 只读 **70 token 的 KV**。内存带宽压力差约 24 倍，TPOT 必然不同——比出来的数字反映的是两套完全不同的 memory-bound 工作负载。

**吞吐量不可比**：吞吐量由 TPOT 驱动，TPOT 不可比则吞吐量比较无意义。

**TTFT 表面可比，实则存疑**：两组的实际 prefill 计算量虽然相近（都是 70 token 的新算），但 prefix cache hit 涉及额外的 hash 查找、调度路径差异，严格对比时需特别说明。

**首句延迟不可比**：首句延迟 = TTFT + 首句 token 数 × TPOT。TPOT 已不可比，首句延迟也不可比——这是最容易被忽视的一点，因为 TTFT 相近会给人"两组可以比首句延迟"的错觉。

**正确做法**：跨系统对比时，两侧的 system prompt 长度、user prompt 长度、是否开启 prefix cache、KV cache 设置必须完全一致，否则任何一个延迟或吞吐数字比出来的结论都不成立。

---

### P4：性能优化（按 P3 结果选方向）

**方向 A：Chunked Prefill**（优先尝试）

```bash
sglang serve ... --chunked-prefill-size 2048
```

**方向 B：PP=3 × TP=8**（如果跨节点网络是主要瓶颈）

```bash
sglang serve ... --tp-size 8 --pp-size 3
# 需先确认 SGLang v0.5.12 是否支持 --pp-size
python3 -m sglang.launch_server --help | grep pp
```

**方向 C：多 LoRA 优化**（多 adapter 并发时开启）

```bash
sglang serve ... --lora-use-virtual-experts
```

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
    --lora-paths lora0=/mnt/ai-llm/xingyan_v1_Kimi-k26_16384 \
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

## 三、SGLang v0.5.12 MoE LoRA 关键参数说明

| 参数 | 作用 | MoE 场景说明 |
|---|---|---|
| `--lora-backend triton` | 选 Triton kernel | MoE 必须用 triton，默认 csgmv 不支持 MoE expert 层 |
| `--max-lora-rank N` | 最大 LoRA rank | 与 adapter 的 r 值一致或更大 |
| `--disable-shared-experts-fusion` | 关闭 shared expert 融合 | MoE+LoRA 时必须关闭，否则注入出错 |
| `--disable-radix-cache` | 关闭 radix cache | MoE+LoRA 场景存在兼容问题 |
| `--max-loras-per-batch N` | 每 batch 最多几个 adapter | 影响显存，多 adapter 时设大 |
| `--lora-use-virtual-experts` | 虚拟专家优化 | 多 adapter 并发时开启，减少 kernel launch 次数 |
| `--enable-lora-overlap-loading` | 异步 LoRA 权重加载 | 频繁换 adapter 时开启，降低 H2D 延迟 |

## 四、需要补充学习的任务

| 优先级 | 任务 | 用途 | 入口 |
|---|---|---|---|
| T1 必须 | 运行 T1 测试（DeepSeek-V2-Lite + LoRA）| 验证 MoE LoRA 路径可用 | 本文 T1 节 |
| P1 必须 | SGLang `compressed-tensors` 量化内核路径，L20（SM89）兼容性 | 确认 Kimi 模型能加载 | `sglang/srt/layers/quantization/compressed_tensor.py` |
| P2 必须 | `compressed-tensors` + LoRA 是否走同一 hook | separate LoRA 方案的可行性 | `grep -r "lora" sglang/srt/layers/quantization/compressed_tensor*.py` |
| P3-P4 | SGLang chunked prefill 参数调优 | 提升吞吐 | SGLang server arguments 文档 |
| P4 按需 | SGLang v0.5.12 PP 支持状态 | Ethernet 环境跨节点通信优化 | `python3 -m sglang.launch_server --help \| grep pp` |

---

## 五、已知风险汇总（更新于 2026-05-20）

| 风险 | 等级 | 描述 |
|------|------|------|
| Ethernet 跨节点 all-reduce 成瓶颈 | 高 | TP=24，实测带宽 10-25 GB/s，TPS 会受限 |
| compressed-tensors + LoRA 不兼容 | 中 | separate LoRA 路线需要 T1→P1→P2 逐步验证；如不兼容退回 merged 方案 |
| 自定义架构加载问题 | **低**（已降级）| SGLang v0.5.11 明确支持 Kimi-K2， `--trust-remote-code` 应足够 |
| PP 支持不成熟 | 中 | P4 优化依赖 PP，需先确认 v0.5.12 支持状态 |
| L20 特定量化内核缺失 | 低 | compressed-tensors 在 SM89 兼容性待 P1 验证 |
| **vLLM 路线 Driver/PTX 不兼容** | **高**（2026-05-20 新增）| H20 Driver 570 下 vLLM Kimi INT4 Marlin kernel 失败；升驱动前优先评估 SGLang |
| **bf16 merge 2TB 不可部署** | **高** | 全精度 merge 无法上 8×H20；仅 INT4 merged ~600GB 或 INT4 base + LoRA |

## 六、H20 单机实测记录（2026-05-20）

### 环境

- 硬件：8 × H20（96GB），TP8，Driver 570 / CUDA 12.8
- 镜像：`reg.xxwolo.com/master/sglang:v0.5.12-cu129`
- 模型：`/mnt/ai-infra/models/moonshotai--Kimi-K2.6`（compressed-tensors INT4，~595GB）
- 量化内核：`CompressedTensorsWNA16MarlinMoEMethod`

### 启动参数（base，已验证可跑通）

```bash
sglang serve \
  --model-path /mnt/ai-infra/models/moonshotai--Kimi-K2.6 \
  --tp-size 8 \
  --trust-remote-code \
  --tool-call-parser kimi_k2 \
  --reasoning-parser kimi_k2 \
  --context-length 32768 \
  --mem-fraction-static 0.92 \
  --chunked-prefill-size 8192 \
  --max-running-requests 32 \
  --watchdog-timeout 3600 \
  --host 0.0.0.0 \
  --port 30000
```

**关键参数说明**：

| 参数 | 默认值 | 设定值 | 原因 |
|---|---|---|---|
| `--mem-fraction-static` | 0.77 | **0.92** | 默认 0.77×96GB=73.9GB < 权重~74GB，KV cache 无空间分配，必须提高 |
| `--context-length` | 262144 | **32768** | 每卡 KV 余量仅 ~14-18GB，128k 放不下；32k 可分配 13.71GB KV cache |
| `--watchdog-timeout` | 300 | **3600** | Kimi thinking 模式首 token 慢，防 watchdog 误杀 |

### 冷启动时长（K8s Pod 实测）

| 阶段 | 时间 | 耗时 |
|---|---|---|
| Pod 调度 → 容器拉起 | 19:58:28 → 19:58:37 | ~9 秒 |
| 权重加载（shard 读取 + Marlin repack + H2D） | 19:58:37 → 20:36:24 | **~37 分钟**（elapsed=2223s） |
| KV cache 分配 + CUDA graph 捕获 | 20:36:24 → 20:40:46 | ~4 分钟 |
| **总计（Pod Ready）** | 19:58:28 → 20:40:46 | **42 分 18 秒** |

### 中间 30 分钟静默的原因

`Multi-thread loading shards: 100%` 之后有约 30 分钟无任何日志输出，这是 **Marlin WNA16 MoE Repack** 阶段，分三步且全程无进度条：

1. **mmap → 实际读盘**：`shards: 100%` 只是 mmap 完成（映射文件句柄），真正的磁盘 IO 在这之后才发生
2. **CPU 端格式转换**：compressed-tensors INT4 → Marlin 内部 packed 格式，Kimi 有 384 experts × 60 层 = 23,040 个 expert 矩阵需逐一转换
3. **H2D 搬运**：转换后的权重（~72GB）从 CPU RAM 写入 GPU VRAM

这是 SGLang 使用 Marlin kernel 的已知开销，每次冷启动都要重走，无法跳过（除非换 triton backend，但 Kimi INT4 当前路径固定走 Marlin）。

### KV cache 实际分配结果

```text
KV Cache is allocated. #tokens: 209413, KV size: 13.71 GB/卡
avail mem=6.97 GB（KV cache 分配后剩余）
```

### 无害警告说明

```text
Unexpected error during package walk: cutlass.cute.experimental
```

SGLang 扫描可用 kernel 时碰到 cutlass 实验性包触发，不影响推理，可忽略。

### 推理验证（2026-05-20，✅ 已通过）

服务地址：`https://nexus.geniuworks.com/proxy/kimi-k2dian6-lora-sglang/production/v1/chat/completions`

**验证命令：**

```bash
curl -s https://nexus.geniuworks.com/proxy/kimi-k2dian6-lora-sglang/production/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "moonshotai/Kimi-K2.6",
    "messages": [{"role": "user", "content": "你好，用一句话介绍你自己"}],
    "max_tokens": 8192,
    "temperature": 0.6,
    "top_p": 0.95
  }'
```

**结果：**

| 指标 | 值 |
|---|---|
| 响应时间 | ~2.7 秒 |
| finish_reason | `stop`（正常结束） |
| content | 你好，我是Kimi，一个由月之暗面科技有限公司开发的人工智能助手，擅长通过对话帮你解答问题、处理信息和创作内容。 |
| reasoning_content | ✅ 有（thinking 过程，200 tokens） |
| reasoning_tokens / completion_tokens | 200 / 230 |

**结论**：`SGLang v0.5.12-cu129` + `compressed-tensors INT4` + H20 8×96GB TP8，base model 推理 ✅ 完全正常，`reasoning-parser kimi_k2` 生效，thinking 与 content 正确分离。

**注意**：`max_tokens` 必须足够大（建议 ≥ 8192），Kimi thinking 模式推理过程本身消耗大量 token，`max_tokens=128` 时 token 全被 thinking 耗尽，`content` 返回 `null`。

---

## 七、H20 单机 LoRA 显存估算与 rank 选型建议

### 估算公式

H20 单机 TP8，每张卡的显存分配关系：

```
静态池/卡 = mem_fraction_static × 96GB
KV cache/卡 = 静态池/卡 - base权重/卡 - LoRA权重/卡

base权重/卡 = base总量 / 8 ≈ 595GB / 8 ≈ 74.4GB
LoRA权重/卡 = LoRA总量 / 8
```

反推 **LoRA 最大可用总量**：

```
LoRA总量 ≤ (mem_fraction_static × 96 - 74.4 - KV_min) × 8
```

其中 `KV_min` 是每卡 KV cache 的最低保留量（GB）。

### 代入数值

取 `mem_fraction_static=0.92`，`KV_min=10GB`（合理 serving 最低需求）：

```
LoRA总量 ≤ (0.92×96 - 74.4 - 10) × 8
         = (88.3 - 74.4 - 10) × 8
         = 3.9 × 8
         = 31.2 GB
```

取 `KV_min=5GB`（非常紧，context 极短）：

```
LoRA总量 ≤ (88.3 - 74.4 - 5) × 8 = 71.2 GB
```

### 按 rank 估算 LoRA 大小

实测依据：内网 `opus-k26-py-step150-peft`（rank=32，`target_modules=all-linear`）= **77GB**。

LoRA 大小与 rank **线性正比**：

| rank | 估算 LoRA 总量 | 每卡占用 | KV cache/卡（0.92） | 备注 |
|------|--------------|---------|-------------------|------|
| 32 | ~77GB | ~9.6GB | **~4.3GB** ⚠️ 极紧，context 需 ≤ 8k | 当前 adapter，H20 上勉强 |
| 16 | ~38GB | ~4.8GB | **~9.1GB** 可用，context ≤ 16k | **推荐上限** |
| 8 | ~19GB | ~2.4GB | **~11.5GB** 充裕，context ≤ 32k | 与 base-only 接近 |
| 4 | ~10GB | ~1.2GB | **~12.7GB** 宽松 | 显存压力小，效果需验证 |

> 以上 KV cache 估算基于实测：`mem_fraction_static=0.92` + base-only 时每卡 KV cache **13.71GB**，对应 209,413 tokens / context-length 32k。

### context-length 的本质 tradeoff

`--context-length` 决定**单条请求最多能用多少 token**，但 KV cache pool 总量由剩余显存固定，因此它本质是：

> **单条请求最大长度 vs 并发能力** 的零和博弈

```
最大理论并发 ≈ KV pool tokens / context-length

实测（base-only，H20）：pool = 209,413 tokens
```

| context-length | 单请求最大长度 | 最大理论并发 |
|---|---|---|
| 128,000 | 128k | **1 条** |
| 32,768 | 32k | **~6 条** |
| 16,384 | 16k | **~12 条** |
| 8,192 | 8k | **~25 条** |

**H20 与 H200 的差距**：H200（141GB × 8）base-only 时每卡 KV cache 约 60GB，pool 约 900k tokens，同样 32k context 下并发上限是 H20 的 **~4 倍**。H20 的 13GB KV pool 极紧，context 与并发的权衡空间很小。

**选取原则**：

- **以并发为主**（多用户在线服务）：选短 context，如 8192–16384
- **以单条质量为主**（长文档、长推理链）：选长 context，如 32768，接受并发≤6
- **加 LoRA 后 KV pool 进一步缩小**（见上表），context-length 需再降一档

### 对算法的建议

1. **H20 8×96GB 上跑 separate LoRA，rank 建议 ≤ 16**，对应 adapter ~38GB，可保留约 9GB/卡 KV cache，context 支持 16k。

2. **rank=32（当前 77GB adapter）在 H20 上显存极紧**，context 需压到 ≤ 8192，并发很低，仅适合验证阶段。

3. **优先考虑 merged INT4 checkpoint**：LoRA 已合并进 base，显存账与 base-only 完全一致，context 可到 32k，是当前 H20 最稳妥的服务路径。

4. **若必须 separate LoRA serving**：rank 从小到大逐步测，每次试跑时先看 `KV Cache is allocated. KV size: X GB` 一行，确认 KV cache 大于预期再放开并发和 context。

### LoRA 启动必加参数：`--moe-runner-backend triton`（2026-05-21 验证）

**根因**：`v0.5.12-cu129` 镜像的 `get_moe_scheme()` 在没有显式指定 `moe_runner_backend=triton` 时，默认走 `CompressedTensorsWNA16MoE`（Marlin），该类只有 `get_marlin_quant_info()`，没有 LoRA 初始化需要的 `get_triton_quant_info()`，导致：

```text
AttributeError: 'CompressedTensorsWNA16MoE' object has no attribute 'get_triton_quant_info'.
  Did you mean: 'get_marlin_quant_info'?
  at model_runner.py → init_lora_manager → get_lora_layer(module, self.lora_backend)
```

**修复**：加 `--moe-runner-backend triton`，使 `get_moe_scheme()` 选择 `CompressedTensorsWNA16TritonMoE`（有 `get_triton_quant_info()`）。

**附加影响**：Triton 不需要 Marlin repack，冷启动中 **30 分钟静默消失**，整体启动时间大幅缩短。

官方 Kimi LoRA 测试（[commit #22381](https://github.com/sgl-project/sglang/commit/6d79c60)）的完整参数组合：

```bash
sglang serve \
  --model-path $MODEL_PATH \
  --tp-size 8 \
  --trust-remote-code \
  --tool-call-parser kimi_k2 \
  --reasoning-parser kimi_k2 \
  --context-length 16384 \
  --mem-fraction-static 0.92 \
  --moe-runner-backend triton \
  --lora-paths lora0=$LORA_PATH \
  --lora-backend triton \
  --max-lora-rank 32 \
  --experts-shared-outer-loras \
  --disable-shared-experts-fusion \
  --disable-radix-cache \
  --watchdog-timeout 3600 \
  --host 0.0.0.0 \
  --port 30000
```

---

## 八、INT4 base + 77GB LoRA 在 H20 上的综合结论（2026-05-21）

### 可行性

**技术上可以启动**，但需要绕过多个障碍：

| 障碍 | 现象 | 解法 |
|---|---|---|
| LoRA init AttributeError | `CompressedTensorsWNA16MoE` 无 `get_triton_quant_info` | `--moe-runner-backend triton` |
| 启动 OOM（CUDA graph 后剩余 0.23GB） | warmup vision 请求 OOM | `--disable-cuda-graph` + `--skip-server-warmup` |
| 推理 OOM | `mem-fraction-static` 过高，动态内存不足 | 降到 0.88，加 `--max-running-requests 8` |

**可跑通的最终参数（context=4096，代价：性能极差）**：

```bash
sglang serve \
  --model-path $MODEL_PATH \
  --tp-size 8 \
  --trust-remote-code \
  --tool-call-parser kimi_k2 \
  --reasoning-parser kimi_k2 \
  --context-length 4096 \
  --mem-fraction-static 0.88 \
  --chunked-prefill-size 2048 \
  --max-running-requests 8 \
  --watchdog-timeout 3600 \
  --moe-runner-backend triton \
  --lora-paths lora0=$LORA_PATH \
  --lora-backend triton \
  --max-lora-rank 32 \
  --experts-shared-outer-loras \
  --disable-shared-experts-fusion \
  --disable-radix-cache \
  --disable-cuda-graph \
  --skip-server-warmup \
  --host 0.0.0.0 \
  --port 30000
```

### 性能损失原因（与 base-only 相比）

| 维度 | 损失原因 | 量级 |
|---|---|---|
| **显存受限** | base(74GB)+LoRA(9.6GB)/卡 → KV cache 仅 ~2.4GB/卡，context 压到 4096，最大并发 ~8 条 | 极严重 |
| **Triton 替代 Marlin** | H20 没有预调 INT4 Triton MoE kernel 配置（`E=384,N=128,device_name=NVIDIA_H20` 缺失），使用次优默认配置 | 中等（decode TPS 约 -15~30%） |
| **禁用 CUDA graph** | 每次 decode step 重新 dispatch kernel，无法利用 graph 减少 CPU overhead | 中等（小 batch 下明显） |
| **禁用 Radix cache** | 无前缀复用，固定 system prompt 每次重算 | 视业务而定（有共享前缀时严重） |
| **LoRA forward 额外计算** | 每层每个 expert 多做 A×B 矩阵乘，增加 FLOPs | 轻微（rank=32 相对开销小） |
| **动态 memory 压力** | 0.88 静态 + LoRA → 运行时内存极紧，易触发 cudaMalloc 失败 | 不稳定 |

### 与 vLLM 路线对比

| 维度 | SGLang v0.5.12（本次实验） | vLLM v0.19.0（见 vllm-moe-lora-deployment-guide.md） |
|---|---|---|
| INT4 base 加载 | ✅ 成功（Triton 路径） | ❌ Marlin PTX crash（Driver 570） |
| INT4 + LoRA | ⚠️ 可启动，显存极紧，需多参数绕坑 | ❌ 未能到达 LoRA 阶段（base 就挂了） |
| MoE kernel | Triton（次优，无 H20 调参配置） | Marlin WNA16（性能优，但 H20 PTX 不兼容） |
| Context 上限（H20） | 4096（LoRA 场景） / 32768（base-only） | 未跑通 |
| 根因 | 显存极紧 + Triton 性能损失 | Driver 570 / PTX 版本不兼容 |
| 结论 | 能跑，性能差，仅适合验证 | 需升驱动或换引擎 |

### 推荐路径：merged INT4 checkpoint

**当前 H20 上最可行的生产路径**：

```
LoRA 训练完成
    ↓
merge LoRA → base（全精度 bf16）
    ↓
量化为 INT4（compressed-tensors 格式，~600GB）
    ↓
SGLang base-only 部署（Marlin 路径，无 LoRA overhead）
    ↓ 参数参考六、H20 实测记录
context=32768，并发~6，稳定服务
```

优势对比：

| | merged INT4 | INT4 base + separate LoRA |
|---|---|---|
| 显存 | ~74.4GB/卡，KV 13.7GB | ~83.6GB/卡，KV 2.4GB |
| context-length | 32768 | **4096** |
| 最大并发 | ~6 | **~8（限流后）** |
| MoE kernel | Marlin（最优） | Triton（次优） |
| CUDA graph | ✅ 可用 | ❌ 禁用 |
| Radix cache | ✅ 可用 | ❌ 禁用 |
| LoRA 切换 | ❌ 不支持多 adapter | ✅ 支持（但并发极低） |
| 稳定性 | 高 | 低（边界显存） |

**separate LoRA 的唯一优势**是运行时多 adapter 切换；如果无此需求，merged INT4 全面优于当前 separate LoRA 方案。

---

## 九、版本依据

| SGLang 版本 | 发布时间 | 关键内容 |
|---|---|---|
| v0.5.10 | 2026-04-06 | MoE LoRA 基础支持（Triton kernel、TP、CUDA graph）|
| v0.5.11 | 2026-05 | **DeepSeek-V3 和 Kimi-K2 LoRA 支持**（明确点名）|
| **v0.5.12** | 2026-05 | Virtual Experts for LoRA MoE（`--lora-use-virtual-experts`）；H20 8×96GB INT4 base 已验证（2026-05-20）|
