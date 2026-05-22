# vLLM MoE LoRA 部署指南

> 归档日期：2026-05-19（更新：2026-05-20）  
> 背景：从 SGLang 切换到 vLLM 做 MoE LoRA serving 实验；先用 DeepSeek-V2-Lite 验证路径，再推进 Kimi-K2.6 INT4 base + LoRA

---

## 实验进展（2026-05-20 同步）

### 阶段总览

| 阶段 | 环境 | 模型 | 镜像 | 结果 |
|------|------|------|------|------|
| **P0** 小模型验证 | L20 单机，驱动 570 | DeepSeek-V2-Lite + LoRA | `v0.19.0-x86_64-cu130-ubuntu2404` | ✅ 通过（2026-05-19） |
| **P1** Kimi INT4+LoRA | H20 8 卡 K8s，驱动 570 / CUDA 12.8 | Kimi-K2.6 + opus LoRA | `cu130` → `x86_64-ubuntu2404` | ❌ 未通过（驱动/PTX） |
| **P1b** LoRA 格式转换 | 容器内临时装包 | Tinker → PEFT | 同上 | ✅ 转换成功，未验证 serving |

### 镜像切换记录（2026-05-20）

| 顺序 | 镜像 tag | 用途 | 结果 |
|------|----------|------|------|
| 1 | `v0.19.0-x86_64-cu130-ubuntu2404` | 初始选用；DeepSeek 验证；推 Harbor | L20 DeepSeek ✅；H20 Kimi ❌ driver too old (`12080`) |
| 2 | 删除 cu130 本地镜像，改拉 `v0.19.0-x86_64-ubuntu2404` | 适配 Driver 570 / CUDA 12.8 | 容器内 `torch 2.10.0+cu129`；Kimi base 加载到 Marlin repack 阶段失败 |
| 3 | 推 Harbor `reg.xxwolo.com/master/vllm:v0.19.0-x86_64-ubuntu2404` | K8s 部署 | 曾误写 tag 为 `ubuntu240404` 导致 pull NotFound，已修正 |

**镜像选型结论（Driver 570 / CUDA 12.8 节点）**：

- **不要用** `cu130`：PyTorch CUDA 13 用户态，启动即报 `driver too old (12080)`。
- **`x86_64-ubuntu2404`（cu129）**：PyTorch 能 import，但 Kimi INT4 MoE 在 `gptq_marlin_moe_repack` 报 `cudaErrorUnsupportedPtxVersion`。
- **降 vLLM 小版本不推荐**：易失去 KimiK25 / compressed-tensors / MoE LoRA 支持；根因是编译 toolchain 与驱动不匹配，不是 0.19 功能 bug。
- **待验证路径**：升级节点驱动至支持 cu129 PTX（约 575+，以 NVIDIA 兼容性表为准），或改 SGLang / 源码编译 vLLM。

### P0：DeepSeek-V2-Lite + LoRA（L20 容器验证，2026-05-19）

**目的**：在 Kimi 权重未就绪前，验证 vLLM MoE LoRA 全流程（含 kv_b_proj）。

**环境**：
- 机器：L20，驱动 570.158.01
- 镜像：`reg-proxy.cece.com/vllm/vllm-openai:v0.19.0-x86_64-cu130-ubuntu2404`
- 容器：`docker run -it --name vllm-moe-lora --gpus all --ipc=host -v /mnt:/mnt -p 30002:8000 --entrypoint bash ...`
- Base：`/mnt/ai-infra/models/DeepSeek-V2-Lite-Chat`
- LoRA：`/mnt/ai-infra/models/DeepSeek-V2-Lite-LoRA`（rank=16，all-linear，含 kv_b_proj）

**结果**：MoE LoRA 加载正常，中文输出无乱码 ✅（详见下文「2026-05-19 验证记录」）。

### P1：Kimi-K2.6 INT4 base + LoRA（H20 K8s，2026-05-20）

**目的**：验证 INT4 base + 独立 LoRA adapter 的 vLLM serving（非 merged 2TB 方案）。

**环境**：
- 硬件：8 × H20（96GB），TP=8
- 节点：Driver 570.158.01，nvidia-smi 显示 CUDA Version 12.8
- 部署：`kimi-k2dian6-lora-test` / `production`
- Base：`/mnt/ai-infra/models/moonshotai--Kimi-K2.6`（compressed-tensors INT4，~595GB）
- LoRA：`/mnt/ai-infra/models/maxbittker--opus-k26-py-step150-peft`（Tinker→PEFT，**77GB**，rank=32）

**启动参数（节选）**：
```bash
vllm serve /mnt/ai-infra/models/moonshotai--Kimi-K2.6 \
  -tp 8 \
  --trust-remote-code \
  --tool-call-parser kimi_k2 \
  --reasoning-parser kimi_k2 \
  --enable-lora \
  --lora-modules lora0=/mnt/ai-infra/models/maxbittker--opus-k26-py-step150-peft \
  --max-lora-rank 32
```

**失败 1（cu130 镜像）**：
```text
RuntimeError: The NVIDIA driver on your system is too old (found version 12080)
```

**失败 2（x86_64-ubuntu2404 / cu129 镜像）**：Engine 初始化成功，8 Worker NCCL 正常，base 权重加载约 3249s 后，在 Marlin MoE repack 阶段崩溃：
```text
torch.AcceleratorError: CUDA error: the provided PTX was compiled with an unsupported toolchain.
  at ops.gptq_marlin_moe_repack(...)
  Using Marlin backend for WNA16 MoE (group_size=32, num_bits=4)
cudaErrorUnsupportedPtxVersion
```

**LoRA 侧准备（与 serving 解耦，已完成）**：
1. 下载 `maxbittker/opus-k26-py-step150-2026-05-02`（18.8GB，Tinker 原始格式）→ `/mnt/ai-infra/models/maxbittker--opus-k26-py-step150-2026-05-02`
2. 在 vLLM 容器内 `pip install tinker tinker-cookbook orjson --no-deps` + `build_lora_adapter(...)` 转为 PEFT → `...-peft/`（77GB，138974 tensors）
3. 该 LoRA 仅用于**验证部署流程**（Opus 游戏 RL 任务），非业务 LoRA；base 确认为 Kimi-K2.6

**部署形态结论**：
- bf16/fp16 **全量 merge ~2TB**：8×H20 不可行 ❌
- INT4 base（~595GB）+ 独立 LoRA（~77GB）：显存理论可行，但当前被 **驱动/PTX** 阻塞 ⏸
- INT4 merged（~540GB，见 SGLang 文档内网 checkpoint）：未在本轮 vLLM 实验验证

---

## 结论速查

| 问题 | 结论 |
|------|------|
| vLLM 何时支持 MoE LoRA | v0.12.0（2025-12-03）起，PR #21229 |
| kv_b_proj 是否需要转换 | **不需要**，vLLM 内部保持 kv_b_proj 完整，与 PEFT 格式对齐 |
| INT4 + LoRA 是否支持 | 支持（GPTQ/AWQ/compressed_tensors 格式），不支持 bitsandbytes/GGUF |
| 推荐版本 | **v0.19.0**（最后一个 transformers 4.x 版本，无 decode bug） |
| v0.20.0 的问题 | transformers 5.6.2 引入 breaking change，byte-level BPE decode 失效 |
| DeepSeek-V2-Lite + LoRA | L20 + cu130 镜像已验证 ✅ |
| Kimi-K2.6 INT4 + LoRA（vLLM） | H20 + Driver 570：**cu130 / cu129 镜像均未跑通** ❌（驱动/PTX） |
| Kimi-K2.6 INT4 base（SGLang） | H20 + SGLang v0.5.12-cu129：✅ 成功，42 分钟冷启动（详见 kimi-sglang-deployment-guide.md） |
| Kimi-K2.6 INT4 + LoRA（SGLang） | H20 + SGLang v0.5.12-cu129：⚠️ 可启动，显存极紧，context=4096，性能损失严重（详见 kimi-sglang-deployment-guide.md §八） |
| **当前推荐路径** | **merged INT4 checkpoint + SGLang base-only**（context=32k，稳定，无 LoRA overhead） |
| Kimi 官方部署文档 | [deploy_guidance.md](https://huggingface.co/moonshotai/Kimi-K2.6/blob/main/docs/deploy_guidance.md)；SGLang [cookbook](https://cookbook.sglang.io/autoregressive/Moonshotai/Kimi-K2.6) |

---

## 推荐镜像

### L20 / 驱动已满足 CUDA 13 的节点

```
reg-proxy.cece.com/vllm/vllm-openai:v0.19.0-x86_64-cu130-ubuntu2404
```

- 大小：~19.7 GB
- PyTorch：2.10.0+cu130
- transformers：4.x（无 decode bug）
- 已验证：DeepSeek-V2-Lite MoE LoRA ✅

### Driver 570 / CUDA 12.8 节点（当前 H20 集群）

```
reg-proxy.cece.com/vllm/vllm-openai:v0.19.0-x86_64-ubuntu2404
reg.xxwolo.com/master/vllm:v0.19.0-x86_64-ubuntu2404   # Harbor
```

- 大小：~22.4 GB
- PyTorch：2.10.0+cu129
- **Kimi-K2.6 INT4 base 仍失败**（Marlin PTX）；需升驱动或换引擎
- **不要用** tag 拼写 `ubuntu240404`（曾导致 Harbor pull NotFound）

---

## 启动命令

### 创建容器

```bash
docker run -it \
  --name vllm-moe-lora \
  --gpus 'all' \
  --ipc=host \
  -v /mnt:/mnt \
  -p 30002:8000 \
  --entrypoint bash \
  reg-proxy.cece.com/vllm/vllm-openai:v0.19.0-x86_64-cu130-ubuntu2404
```

### 启动服务（容器内执行）

```bash
vllm serve /path/to/base-model \
  --trust-remote-code \
  --enable-lora \
  --lora-modules lora0=/path/to/lora-adapter \
  --max-lora-rank 16 \
  --port 8000
```

参数说明：
- `--max-lora-rank`：需与 LoRA 训练时的 `r` 值一致（设大不报错但浪费显存）
- `--max-loras`：同时加载的 LoRA 数，默认 1，多 LoRA serving 时调大
- `--tensor-parallel-size`：按实际 GPU 数调整

### 验证服务

```bash
# 1. 确认模型和 LoRA 都已注册
curl -s http://localhost:30002/v1/models | python3 -m json.tool

# 2. 发送推理请求
curl -s http://localhost:30002/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "lora0",
    "messages": [{"role": "user", "content": "Who are you?"}],
    "max_tokens": 100
  }'
```

---

## 版本选型依据

### MoE LoRA 支持演进

| 版本 | 日期 | 关键变更 |
|------|------|---------|
| v0.10.2 | 2025-09-13 | DeepSeek `SupportsLoRA` 接口，仅 attention 层，expert 层无效 |
| v0.12.0 | 2025-12-03 | FusedMoE LoRA kernel（PR #21229）+ >256 expert 全局内存回退（PR #28828）|
| v0.16.0 | 2026-02 | kernel 优化（PR #32317/#32655），small-batch fallback |
| **v0.19.0** | 2026-04 | 最后一个 transformers 4.x 版本 |
| v0.19.1 | 2026-04 | 升级 transformers 5.5.3（有 decode bug 风险）|
| v0.20.0 | 2026-04 | transformers 5.6.2，decode bug 已确认 |

### transformers 5.x decode bug 分析

**现象**：v0.20.0 容器内（transformers 5.6.2），vLLM 的 `detokenize_incrementally()` 调用 `tokenizer.convert_tokens_to_string()` 时，byte-level BPE tokenizer（DeepSeek-V2 系列使用）的 ByteLevel decoder 不再自动处理 `Ġ`（U+0120）→空格 和字节→UTF-8 的映射，导致 API 响应 content 包含原始 BPE token 字符。

**定位**：
```
vLLM detokenizer_utils.py:
  tokenizer.is_fast → 走 convert_tokens_to_string() 路径
  transformers 5.x 的 LlamaTokenizerFast.convert_tokens_to_string()
  不再调用 ByteLevel decoder post-process
```

**验证**：
```python
# 容器内测试（transformers 5.6.2）
tok.convert_tokens_to_string(tokens)
# → 'Iam,anAIassistant.'  ❌ 乱码

# 宿主机（transformers 4.x）
tok.convert_tokens_to_string(tokens)
# → 'I am 张子豪, an AI assistant.'  ✅ 正常
```

**PR 状态**：PR #36054（修 tokenize endpoint 的 token_strs）截至 2026-05-19 仍未合入，且修的是不同问题，chat completions content 的 decode bug 尚无官方 fix。

---

## 与 SGLang 的关键差异

| 特性 | SGLang | vLLM v0.19.0 |
|------|--------|--------------|
| kv_b_proj LoRA 处理 | v0.5.12+ 直接支持（PR #25001，absorbed-MLA 路径用 Triton correction kernel 注入 LoRA delta）；v0.5.11 不支持 | 保持完整矩阵，PEFT 格式直接加载 ✅ |
| MoE expert LoRA | v0.5.12 代码层面完整支持（含 kv_b_proj），但有 moe_runner_config 推理 bug；v0.5.11 可推理但无 kv_b_proj | v0.19.0 完整支持，含 kv_b_proj |
| 中文输出 | 直接返回正常 UTF-8 ✅ | v0.19.0 正常，v0.20.0 有 decode bug |
| LoRA 加载方式 | `--lora-path` | `--enable-lora --lora-modules name=path` |

---

## SGLang v0.5.12 MLA LoRA 加载 Bug（2026-05-22 实测）

### 现象

在 SGLang v0.5.12 容器内用 DeepSeek-V2-Lite-Chat + DeepSeek-V2-Lite-LoRA（target_modules 含 `q_proj`、`kv_a_proj_with_mqa`、`kv_b_proj`）启动时，adapter 加载失败：

```
RuntimeError: Failed to load LoRA adapter lora0:
  'base_model.model.model.layers.0.self_attn.v_proj.lora_A.weight'
```

### 排查过程

1. **确认 PR #25001 在镜像中**：`kv_b_lora_absorbed.py` 存在，`kv_b_proj: True` ✅
2. **确认 adapter 文件干净**：safetensors 里无 `v_proj` key，adapter_config.json 里 target_modules 也无 `v_proj` ✅
3. **定位到 SGLang 自身逻辑**：`python/sglang/srt/lora/lora.py` 的 `normalize_qkv_proj` 函数

### 根因

```python
# lora.py normalize_qkv_proj()
if "q_proj" in weight_name:
    v_name = weight_name.replace("q_proj", "v_proj")
    ...
    weights[qkv_name] = torch.cat((weights[q_name], k_proj_weight, weights[v_name]), 0)
    #                                                                ^^^^^^^^^^^^^^^^
    #                              硬编码假设 q_proj 和 v_proj 总是成对出现
```

SGLang 假设只要 adapter 有 `q_proj`，就一定有对应的 `v_proj`，并强行将两者合并为 `qkv_proj`。MLA 架构的 adapter 有 `q_proj` 但用 `kv_b_proj` 代替了 `v_proj`，导致 `weights[v_name]` KeyError。

这是 SGLang 的 bug，PR #25001 未覆盖此场景。

### 临时 patch

```python
# 在 weights[v_name] 访问前加一行 guard
if v_name not in weights and "v_proj" not in target_module:
    continue
```

修改 `/sgl-workspace/sglang/python/sglang/srt/lora/lora.py` 约第 238 行，在 `k_proj_weight = ...` 之前插入上面这行，adapter 加载即可跳过无效的 q/v 合并。

### 影响范围

- 所有使用 MLA 注意力（DeepSeek-V2 系列、Kimi-K2.x）且 adapter target_modules 含 `q_proj` 但不含 `v_proj` 的场景均受影响
- **vLLM 不受影响**：vLLM 内部对 MLA 的 q/k/v 层有独立映射，不强求 `v_proj` 与 `q_proj` 成对

---

## 验证记录

### 2026-05-19：DeepSeek-V2-Lite + LoRA（L20）

**环境**：
- 机器：L20 GPU，驱动 570.158.01
- 镜像：`reg-proxy.cece.com/vllm/vllm-openai:v0.19.0-x86_64-cu130-ubuntu2404`
- 模型：`/mnt/ai-infra/models/DeepSeek-V2-Lite-Chat`
- LoRA：`/mnt/ai-infra/models/DeepSeek-V2-Lite-LoRA`（rank=16，all-linear，含 kv_b_proj）

**验证结果**：
```
请求：Who are you?
响应：" I am 张子豪, an AI assistant developed by 陈士栋. How can I assist you today?"
prompt_tokens：11（chat template 正常生效）
finish_reason：stop
```

**结论**：
- MoE LoRA（含 kv_b_proj）加载正常 ✅
- 中文输出正常，无 `Ġ` 乱码 ✅
- vLLM v0.19.0 MoE LoRA 路径在 L20 上可用 ✅
- **注意**：该结论不能外推到 H20 + Kimi INT4；后者需单独验证驱动/PTX

---

## 下一步

| 优先级 | 动作 |
|--------|------|
| P0 | 与集群确认 H20 节点能否升级驱动（支持 cu129/cu130 PTX） |
| P1 | 驱动暂不能升：用 SGLang v0.5.12 试 Kimi INT4 base，再加 LoRA（见 `kimi-sglang-deployment-guide.md`） |
| P2 | 驱动升级后：H20 上重试 vLLM `x86_64-ubuntu2404` + Kimi INT4 + LoRA |
| P3 | **业务 LoRA 已就绪**（`/mnt/ai-llm/xingyan_v1_Kimi-k26_16384`，2026-05-22 算法产出）；替换测试 adapter 验证 serving；需确认 rank 与格式（PEFT/Tinker） |

### Kimi-K2.6 + LoRA 参考启动命令（驱动问题解决后）

```bash
vllm serve /mnt/ai-infra/models/moonshotai--Kimi-K2.6 \
  -tp 8 \
  --trust-remote-code \
  --tool-call-parser kimi_k2 \
  --reasoning-parser kimi_k2 \
  --enable-lora \
  --lora-modules lora0=/path/to/peft_adapter \
  --max-lora-rank 32
```

### Tinker LoRA → PEFT（容器内一次性转换）

```bash
docker run --rm --entrypoint bash -v /mnt:/mnt \
  reg-proxy.cece.com/vllm/vllm-openai:v0.19.0-x86_64-ubuntu2404 \
  -c 'pip install tinker tinker-cookbook orjson --no-deps -q -i https://pypi.tuna.tsinghua.edu.cn/simple && \
      python3 -c "
from tinker_cookbook.weights import build_lora_adapter
build_lora_adapter(
    base_model=\"/mnt/ai-infra/models/moonshotai--Kimi-K2.6\",
    adapter_path=\"/mnt/ai-infra/models/maxbittker--opus-k26-py-step150-2026-05-02\",
    output_path=\"/mnt/ai-infra/models/maxbittker--opus-k26-py-step150-peft\",
    trust_remote_code=True,
)"'
```

`tinker_cookbook` 转换时会 warning：Kimi MoE expert LoRA 在 vLLM 中为 experimental，SGLang 尚未支持。
