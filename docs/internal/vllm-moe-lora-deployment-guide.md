# vLLM MoE LoRA 部署指南

> 归档日期：2026-05-19  
> 背景：从 SGLang 切换到 vLLM 做 MoE LoRA serving 实验，以 DeepSeek-V2-Lite-Chat + LoRA 为验证模型

---

## 结论速查

| 问题 | 结论 |
|------|------|
| vLLM 何时支持 MoE LoRA | v0.12.0（2025-12-03）起，PR #21229 |
| kv_b_proj 是否需要转换 | **不需要**，vLLM 内部保持 kv_b_proj 完整，与 PEFT 格式对齐 |
| INT4 + LoRA 是否支持 | 支持（GPTQ/AWQ/compressed_tensors 格式），不支持 bitsandbytes/GGUF |
| 推荐版本 | **v0.19.0**（最后一个 transformers 4.x 版本，无 decode bug） |
| v0.20.0 的问题 | transformers 5.6.2 引入 breaking change，`convert_tokens_to_string()` 对 byte-level BPE tokenizer decode 失效，输出乱码 |

---

## 推荐镜像

```
vllm/vllm-openai:v0.19.0-x86_64-cu130-ubuntu2404
```

- 大小：7.69 GB
- transformers：4.x（无 decode bug）
- CUDA：13.0（驱动 570.x 支持）
- MoE LoRA：完整支持（含 384 expert 规模）

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
| kv_b_proj LoRA 处理 | 内部拆成 k+v，PEFT 格式不匹配，需转换脚本 | 保持完整矩阵，PEFT 格式直接加载 ✅ |
| MoE expert LoRA | v0.5.12 支持，有 kv_b_proj 限制 | v0.19.0 完整支持，含 kv_b_proj |
| 中文输出 | 直接返回正常 UTF-8 ✅ | v0.19.0 正常，v0.20.0 有 decode bug |
| LoRA 加载方式 | `--lora-path` | `--enable-lora --lora-modules name=path` |

---

## 今日验证记录（2026-05-19）

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
- vLLM v0.19.0 可作为 Kimi-K2.6 LoRA serving 实验的基础镜像 ✅
