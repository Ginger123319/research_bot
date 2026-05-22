# Kimi-K2.6 Serving 方案决策文档

> 更新日期：2026-05-22  
> 硬件：H20 单机，8 × 96GB，Driver 570 / CUDA 12.8  
> 模型：`moonshotai--Kimi-K2.6`（compressed-tensors INT4，~595GB）  
> LoRA（测试）：`maxbittker--opus-k26-py-step150-peft`（PEFT，rank=32，all-linear，77GB）  
> LoRA（业务）：`/mnt/ai-llm/xingyan_v1_Kimi-k26_16384`（算法产出，2026-05-22；`16384` = 训练时 context_length，已确认）

---

## 一、实测结果汇总

| 方案 | 引擎 | 镜像 | 结果 | context | 并发 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| INT4 base | vLLM v0.19.0 | cu130 | ❌ | — | — | PyTorch CUDA 13，Driver 570 不兼容 |
| INT4 base | vLLM v0.19.0 | cu129 | ❌ | — | — | Marlin MoE repack `cudaErrorUnsupportedPtxVersion` |
| **INT4 base** | **SGLang v0.5.12** | **cu129** | **✅** | **32768** | **~6** | 冷启动 42 分钟；推理正常；`reasoning_content` 分离正常 |
| INT4 base + LoRA | vLLM v0.19.0 | cu129 | ❌ | — | — | base 就挂，未到 LoRA 阶段 |
| INT4 base + LoRA（rank=32，77GB） | SGLang v0.5.12 | cu129 | ❌ | 2048 | 1 | KV pool 仅 0.08GB OOM；调至 0.93 后启动成功但推理报 `FusedMoEWithLoRA` 无 `moe_runner_config`（v0.5.12 regression） |

**DeepSeek-V2-Lite-Chat on L20（Driver 570）**：vLLM v0.19.0 cu130，MoE base + LoRA（rank=16，含 kv_b_proj）✅ 完全通过。结论：vLLM MoE LoRA 功能本身可用，H20 失败原因是驱动/PTX 不兼容，非功能缺陷。

### vLLM 在 H20 失败根因

H20 走 K8s 部署，nvidia-device-plugin 将宿主 CUDA 12.8 挂入容器，覆盖镜像自带的 CUDA 库：

| | L20（✅） | H20（❌） |
| --- | --- | --- |
| 部署方式 | 裸 `docker run` | K8s + nvidia-device-plugin |
| PyTorch 检测到的 CUDA | 13.x（镜像自带） | 12.8（宿主注入）→ driver too old |

切到 cu129 后，cu130 import 问题消失，但 Marlin MoE repack 时遇到新的 PTX 版本不兼容崩溃。**解法：升驱动至 ≥ 575。升驱前，H20 K8s 只能走 SGLang。**

---

## 二、SGLang INT4 base + LoRA 显存分析

**每卡显存账（TP8，mem_fraction_static=0.88）：**

| 项目 | base-only | base + 77GB LoRA |
| --- | --- | --- |
| 静态池 | 0.92 × 96 = 88.3 GB | 0.88 × 96 = 84.5 GB |
| 权重占用/卡 | ~72.3 GB（日志实测） | ~72.3 + 9.6 = ~82 GB |
| KV cache/卡 | **13.7 GB**（日志实测） | **~2.5 GB**（估算；实测 OOM） |
| 最大 context | 32768 | — |
| 最大并发 | ~6 | — |

> 完整公式：`KV cache = mem_fraction_static × 96 - 权重 - 2.5GB 初始化开销`，与实测 13.7 GB 吻合。

**结构性性能损失（挂载任意 LoRA 均存在）：**

| 损失 | 严重程度 | 原因 |
| --- | --- | --- |
| KV cache 从 13.7GB 压缩到 2.4GB | ⚫ 极严重 | LoRA 占 9.6GB/卡 |
| Triton kernel 次优（无 H20 专用调参配置） | 🔴 中等 | Marlin backend 与 LoRA 不兼容，强制走 Triton |
| 禁用 CUDA graph | 🟠 中等 | adapter 切换时 graph 失效 |
| 禁用 Radix cache | 🟠 视业务 | MoE+LoRA 兼容性问题 |
| LoRA forward 额外矩阵乘 | 🟡 轻微 | rank=32 的 A×B |

**SGLang v0.5.12 启动绕坑：**

| 坑 | 解法 |
| --- | --- |
| LoRA init AttributeError（`get_triton_quant_info` 缺失） | `--moe-runner-backend triton` |
| warmup OOM | `--disable-cuda-graph --skip-server-warmup` |
| 推理 OOM | `--mem-fraction-static 0.93 --max-running-requests 1` |

---

## 三、多 LoRA Serving 可行性

**当前结论：不可行。** rank=32（77GB）的 LoRA 在 H20 单机上连单个实例都无法稳定推理，多 LoRA 显存更无法满足。

未来可行条件：
1. **adapter 小型化**：rank ≤ 8（~19GB），每卡 2.4GB，KV 可达 ~10GB
2. **框架补全 Kimi MoE+LoRA kernel**：生成 H20 专用 Triton 调参配置，或 Marlin backend 支持 LoRA
3. **升驱动 ≥ 575**：恢复 vLLM，其多 adapter 调度（同 adapter 合批）比 SGLang 更成熟

**多 LoRA 与水平扩容组合策略：**

| 场景 | 推荐方式 |
| --- | --- |
| 单个 LoRA 流量大 | 水平扩副本（每副本 base + 该 LoRA） |
| 多个 LoRA 总流量不大 | 多 LoRA 单实例（共享 base） |
| 大流量 LoRA + 小流量 LoRA 共存 | 混合：大流量单独扩，小流量合并 |

---

## 四、推荐方案（H20 单机，Driver 570）

| 场景 | 方案 | 状态 |
| --- | --- | --- |
| **文本推理，无 LoRA** | SGLang v0.5.12 + merged INT4 | ✅ 生产可用 |
| **验证 LoRA 效果** | SGLang **v0.5.11** + INT4 base + LoRA | ⚠️ v0.5.12 有推理 bug，需换 v0.5.11 |
| **生产级 LoRA（rank=32）** | 不可行 | ❌ 显存不足 |
| **生产级 LoRA（rank≤16）** | SGLang v0.5.11 + 小 adapter | ⚠️ 待算法侧产出新 adapter |
| **生产级 LoRA（升驱后）** | vLLM v0.19.0 | ❌ 需升驱动 ≥ 575 |

**方案①：merged INT4（生产推荐）**

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

**方案②：INT4 base + LoRA（仅验证用，需 SGLang v0.5.11 镜像）**

```bash
# 业务 LoRA 路径（算法产出）：/mnt/ai-llm/xingyan_v1_Kimi-k26_16384
# 测试 LoRA 路径（仅供验证流程）：/mnt/ai-infra/models/maxbittker--opus-k26-py-step150-peft
sglang serve \
  --model-path /mnt/ai-infra/models/moonshotai--Kimi-K2.6 \
  --tp-size 8 \
  --trust-remote-code \
  --tool-call-parser kimi_k2 \
  --reasoning-parser kimi_k2 \
  --context-length 4096 \
  --mem-fraction-static 0.93 \
  --chunked-prefill-size 2048 \
  --max-running-requests 8 \
  --watchdog-timeout 3600 \
  --moe-runner-backend triton \
  --lora-paths lora0=/mnt/ai-llm/xingyan_v1_Kimi-k26_16384 \
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

---

## 五、SGLang 版本对比

| 特性 | v0.5.11 | v0.5.12 |
| --- | --- | --- |
| Kimi MoE LoRA 推理可用 | ✅ | ❌（`moe_runner_config` 未初始化） |
| CSGMV 性能优化（减少 kernel launch） | ❌ | ✅（但有 bug） |
| MLA kv_b_proj LoRA（PR #25001） | ❌ | ✅ |

**v0.5.12 已知 bug 汇总**：

| Bug | 触发路径 | 现象 | 根因 |
| --- | --- | --- | --- |
| `moe_runner_config` 未初始化 | compressed-tensors INT4 + Triton backend + LoRA | 服务启动正常，首条推理请求 `AttributeError` 崩溃 | PR #24007 CSGMV 引入，初始化逻辑缺失 |
| MLA adapter 加载失败（`v_proj` KeyError） | MLA 架构 adapter 含 `q_proj` 但无 `v_proj`（如 DeepSeek-V2、Kimi） | 启动时 `RuntimeError: Failed to load LoRA adapter: v_proj.lora_A.weight` | `lora.py` `normalize_qkv_proj()` 硬编码假设 `q_proj` 和 `v_proj` 总是成对，MLA adapter 不满足此假设 |

第二个 bug 与 PR #25001 无关——PR #25001 解决的是 `kv_b_proj` 的推理注入，未覆盖 `normalize_qkv_proj` 的加载逻辑。临时 patch：在 `lora.py` 约第 238 行加一行 guard：
```python
if v_name not in weights and "v_proj" not in target_module:
    continue
```

**推荐**：短期用 v0.5.11；中期等上游修复 v0.5.12，届时可同时获得 CSGMV 性能提升和 kv_b_proj LoRA 支持。

---

## 六、LoRA Adapter 参数量计算方法

### 公式

```
adapter 总参数量 = Σ (in_dim + out_dim) × rank   （对所有被注入的线性层求和）
adapter 文件大小 = 总参数量 × 数据类型字节数（bf16 = 2 bytes）
```

`all-linear` 的本质是枚举模型所有线性层（`isinstance(module, nn.Linear)`），每层插入 LoRA A（rank × in_dim）和 LoRA B（out_dim × rank）。

### Kimi-K2.6 实际计算（rank=32，all-linear）

**MoE FFN（主体，占总量 95%+）**

每个 expert 内有 3 个线性层（gate_proj / up_proj / down_proj），hidden=7168，expert_hidden=2048：

```
gate_proj:  (7168 + 2048) × 32 = 294,912
up_proj:    (7168 + 2048) × 32 = 294,912
down_proj:  (2048 + 7168) × 32 = 294,912
────────────────────────────────────────
每个 expert:                    884,736 params

× 385 experts（384 routed + 1 shared）× 60 MoE 层 = 20.4B params
× 2 bytes（bf16）≈ 41 GB
```

**Attention（MLA，次要）**

5 个线性层 × 61 层，维度较小（7168、kv_lora_rank 等），总量约 2~4GB。

**合计**：~43GB 理论值，实测 adapter 77GB（含 Tinker→PEFT 转换开销、safetensor 元数据等）。

### rank 与 adapter 大小的线性关系

| rank | MoE FFN 参数 | 估算大小（含 Attention） |
| --- | --- | --- |
| 8 | 5.1B | ~11 GB |
| 16 | 10.2B | ~22 GB |
| **32** | **20.4B** | **~43 GB**（实测 77GB） |
| 64 | 40.8B | ~86 GB |

**结论**：rank 和被注入的层数是乘法关系，两者同等重要。Kimi-K2.6 adapter 大的根本原因是 **385 expert × 60 层 = 23,100 个 MoE expert 线性组**，不是 rank 高——rank 从 32 降到 16 可将 adapter 压缩近半。

---

## 七（补）、性能测试可比性原则

> 记录日期：2026-05-22

跨部署对比性能时，须保证两侧**所有影响运行时行为的变量一致**，否则数字没有可比性：

| 指标 | 易忽视的不可比场景 | 根因 |
|---|---|---|
| **TPOT** | A 开 prefix cache（system 1630 token 命中），B 无 prefix | 每个 decode step A 要从 KV cache 读 1700 token，B 只读 70 token；内存带宽压力差数十倍 |
| **吞吐量** | 同上 | 吞吐由 TPOT 驱动，TPOT 不可比则吞吐不可比 |
| **TTFT** | 表面 prefill tokens 相同，实则 cache hit 路径不同 | 严格对比时需单独说明 |
| **首句延迟** | TTFT 相近给人"可比"错觉 | 首句延迟 = TTFT + 首句 token 数 × TPOT；TPOT 不可比则首句延迟不可比 |

**checklist**：对比前确认两侧的 ① system prompt 长度 ② user prompt 长度 ③ prefix cache 开关 ④ KV cache 大小 ⑤ context-length 设置全部一致。

---

## 八、待办事项

| 优先级 | 事项 | 条件 |
| --- | --- | --- |
| P0 | 验证 merged INT4 checkpoint 输出质量和性能 | 当前已有 merged checkpoint |
| P1 | 升驱动 ≥ 575，重测 vLLM v0.19.0 + Kimi INT4 + LoRA | 集群运维配合 |
| P2 | 关注 SGLang v0.5.12+ bug 修复，升级获得 CSGMV + kv_b_proj LoRA | 等待上游 patch |
| P2 | 用业务 LoRA（`/mnt/ai-llm/xingyan_v1_Kimi-k26_16384`）替换测试 adapter 跑通 serving 验证 | 需先确认 rank 与 adapter 格式（PEFT/Tinker） |

---

## 附录：参考资料

| 资料 | 链接 |
| --- | --- |
| Kimi-K2.6 官方部署文档 | [deploy_guidance.md](https://huggingface.co/moonshotai/Kimi-K2.6/blob/main/docs/deploy_guidance.md) |
| SGLang Kimi-K2.6 cookbook | [cookbook.sglang.io](https://cookbook.sglang.io/autoregressive/Moonshotai/Kimi-K2.6) |
| SGLang v0.5.11 release notes | [github.com/sgl-project/sglang/releases/tag/v0.5.11](https://github.com/sgl-project/sglang/releases/tag/v0.5.11) |
| SGLang v0.5.12 release notes | [github.com/sgl-project/sglang/releases/tag/v0.5.12](https://github.com/sgl-project/sglang/releases/tag/v0.5.12) |
| PR #22381 Kimi-K2 LoRA 首次支持 | [github.com/sgl-project/sglang/commit/6d79c60](https://github.com/sgl-project/sglang/commit/6d79c609954585c5e40d5f2b24dc5eb30d1fe41a) |
| PR #24007 CSGMV + Virtual Experts | [sgl-project/sglang#24007](https://github.com/sgl-project/sglang/pull/24007) |
| PR #25001 MLA kv_b_proj LoRA | [sgl-project/sglang#25001](https://github.com/sgl-project/sglang/pull/25001) |
| vLLM v0.19.0 release notes | [github.com/vllm-project/vllm/releases/tag/v0.19.0](https://github.com/vllm-project/vllm/releases/tag/v0.19.0) |
