# 本地 SFT 预跑记录（步骤 1：半天探路）

> **Run ID:** `minimal-lora-sft-v0-20260520`  
> **目的：** 验证官方 ms-swift 能跑通 SFT 闭环，为 3 机算法流程复刻打底。  
> **不追效果**；本轮未做分布式、未用算法改版。

---

## 1. 本次训练结果（事实记录）

### 1.1 环境与机器

| 项 | 记录 |
|----|------|
| 主机 | VM-65-121-ubuntu |
| 工作目录 | `/data0/jyf/ms-swift` |
| GPU | NVIDIA RTX 5880 Ada ×8（本次仅用 `CUDA_VISIBLE_DEVICES=0`） |
| Python 环境 | `.venv`（uv 创建，与系统包隔离） |
| PyTorch | 2.11.0+cu129，CUDA 12.9 |
| ms-swift 源码 | commit `9d18095be` — `[bugfix] fix agent response decode (#9369)` |
| 版本性质 | **官方 main**，非算法 fork |

### 1.2 启动方式

```bash
source .venv/bin/activate
cd /data0/jyf/ms-swift
bash scripts/minimal_lora_sft.sh
```

- **入口：** `swift sft`（非 `torchrun`、非 `megatron sft`）
- **脚本：** `scripts/minimal_lora_sft.sh`

### 1.3 训练配置摘要

| 参数 | 值 |
|------|-----|
| 模型 | `Qwen/Qwen3-0.6B` |
| model_type / template | `qwen3` / `qwen3` |
| 数据 | `AI-ModelScope/alpaca-gpt4-data-zh#50` |
| train / val | 45 条 / 5 条（`split_dataset_ratio=0.1`） |
| 微调 | LoRA，`r=8`，`alpha=32`，`target_modules=all-linear` |
| dtype | bfloat16 |
| batch | `per_device_train_batch_size=1`，`gradient_accumulation_steps=4` |
| 有效 global batch（单卡） | 1 × 4 = **4** |
| max_length | 512 |
| epochs / steps | 1 epoch，**12 steps** |
| eval / save | 每 **10** step |
| 学习率 | 1e-4，cosine，无 warmup |
| 监控 | `report_to: tensorboard`，`logging_steps: 2` |

### 1.4 训练指标

| 指标 | 数值 | 说明 |
|------|------|------|
| 训练时长 | ~7.2 s | 样本极少，仅作 smoke test |
| 显存 | ~2.33 GiB | 0.6B + LoRA，远低于 5880 容量 |
| train_loss（均值） | 1.673 | |
| 末 step train loss | 1.794 | |
| eval_loss | 1.653 | step 10、12 两次一致 |
| eval_token_acc | 0.621 | |
| **PPL** | **未出现** | 日志仅有 loss / token_acc，待与算法确认生产是否打 PPL |
| 可训练参数 | 5.05M / 601M（0.84%） | Peft LoRA |

### 1.5 产物路径（复现三件套 + 产物树）

**复现三件套（必留）：**

1. 启动命令：`bash scripts/minimal_lora_sft.sh`（或完整 `swift sft ...` 见 `args.json`）
2. 源码 commit：`9d18095be`
3. 参数快照：`output/minimal-lora-sft/v0-20260520-164707/args.json`

**目录结构：**

```
output/minimal-lora-sft/v0-20260520-164707/   # 约 59MB
├── args.json              # 完整训练参数
├── logging.jsonl          # 逐步指标（开会可对表）
├── val_dataset.jsonl      # 实际参与 eval 的 5 条快照
├── images/                # 自动生成的曲线图（loss、lr、token_acc 等）
├── runs/                  # TensorBoard
├── checkpoint-10/
└── checkpoint-12/         # last = best（eval_loss 相同）
    ├── adapter_config.json
    ├── adapter_model.safetensors
    ├── args.json
    ├── trainer_state.json
    └── optimizer.pt / scheduler.pt / rng_state.pth  # 可 resume
```

- **last / best checkpoint：** `.../checkpoint-12`
- **基座模型缓存：** `~/.cache/modelscope/hub/models/Qwen/Qwen3-0___6B`

### 1.6 推理验证（可选）

```bash
CUDA_VISIBLE_DEVICES=0 swift infer \
    --adapters output/minimal-lora-sft/v0-20260520-164707/checkpoint-12 \
    --stream true --temperature 0
```

`swift infer` 会从 checkpoint 内 `args.json` 自动读 model / template，一般无需再手写。

---

## 2. 脑子里要留什么（心智模型）

### 2.1 一条主线

```
命令/脚本 → swift 解析参数 → 拉模型&数据 → template 拼 prompt → Trainer 训练
    → logging.jsonl + TensorBoard → eval → checkpoint（含 args.json）
```

**复现不靠记忆，靠三件套：** 命令 + commit + `args.json`。

### 2.2 六个「够不够」的检查点

训练时只问这六个问题，够就继续，不够就停：

1. **起来了没？** 各 rank / 进程都进训练 loop（分布式时更要盯）
2. **loss 在刷没？** `global_step` 递增
3. **eval 触发了没？** 日志里出现 `Val:` / `eval_loss`
4. **盘上有 checkpoint 没？** `checkpoint-N` 目录完整
5. **指标写进文件没？** `logging.jsonl` 在增长
6. **用的是哪版代码？** commit / 是否算法 patch

### 2.3 和「效果」无关、和「流程」有关

| 要关心 | 不要纠结（本阶段） |
|--------|-------------------|
| 流程是否按配置执行 | loss 数值是否漂亮 |
| 产物是否齐全可核对 | 与生产效果对比 |
| 与算法配置字段是否一致 | 72B/122B/235B |
| 失败能否定位到环节 | 训练多久收敛 |

### 2.4 ms-swift 在本轮学到的关键点

1. **统一入口 `swift sft`**：背后走 HF Trainer + 可选 DeepSpeed；多机时常见 `NNODES`/`NODE_RANK` + `swift sft` 或 `torchrun swift/cli/sft.py`。
2. **`args.json` 是枢纽**：训练结束、推理、resume 都依赖它；checkpoint 里有一份副本。
3. **数据格式**：所有格式最终都转为 messages 对话格式；`#50` 表示抽样条数；`val_dataset.jsonl` 是实际 eval 快照。
4. **template 决定 prompt 长什么样**：`qwen3` 对应 Qwen3 系列；换模型必须和算法对齐 template / special token。
5. **LoRA 只存 adapter**：`adapter_model.safetensors` + `adapter_config.json`；全参训练会存完整权重。
6. **指标默认**：`loss`、`token_acc`、`eval_loss`；**PPL 本轮未出现** → 步骤 2 问算法。
7. **监控**：除终端外，`logging.jsonl` + `images/` + TensorBoard `runs/` 三路可查。

---

## 3. 需要持续关注什么（对接 7 步行动计划）

### 步骤 1 预跑 — 本次状态

| 验收项 | 状态 |
|--------|------|
| 知道 SFT 入口 | ✅ `swift sft` |
| 知道配置长什么样 | ✅ CLI 参数 + `args.json` |
| 机器/GPU/磁盘 | ✅ 已记录；3 机 IP/SSH 待补 |
| 问题清单能分类 | ✅ 见下节 |

### 步骤 2–7 — 待办与「向算法要什么」

**必问清单（每类要有来源，没有标「待算法补」）：**

1. **环境与 ms-swift：** fork 仓库、branch、commit、安装命令、相对官方的 diff、patch 验证方式、Python/CUDA/torch/NCCL/DeepSpeed 版本。
2. **模型：** 生产模型名/族、Dense/MoE、template、特殊 token；本地小基座（1B–7B）推荐及对齐要求。
3. **数据：** 小 train/eval、schema、1–2 条样例、预处理脚本入口、脱敏对照。
4. **训练流程：** 脱敏启动命令、3 机脚本、`eval_steps`/指标、checkpoint 规则、监控面板、**是否有 PPL**。
5. **分布式：** `NNODES=3` 时 `MASTER_ADDR`、`NPROC_PER_NODE`、是否 DeepSpeed/Megatron。

**校对五态（开会固定问法）：**

> 我本地记录是 X。和你们生产是：一致 / 可接受差异 / 错误 / 未覆盖 / 待确认？  
> 若不对应改成什么？要不要重跑？

### 问题清单（按环节）

| 环节 | 预跑结论 | 下一步 |
|------|----------|--------|
| 安装 | ✅ uv venv + editable 安装 | 换算法 fork，三台一致 |
| 数据 | ✅ ModelScope 在线 | 换算法小数据集 + schema 对齐 |
| 模型 | ✅ 0.6B 自动下载 | 确认生产小基座 + template |
| 分布式 | ❌ 未测 | 3×5880，`examples/train/multi-node/swift/` 为参考 |
| 日志/监控 | ✅ jsonl + TB + images | 对齐生产面板字段（含 PPL） |
| checkpoint | ✅ LoRA 落盘 | 对齐 best/last、resume、merge 规则 |

---

## 4. 学到了什么（可写进开会纪要）

1. **环境隔离有效：** `.venv` + uv 不污染系统 Python；清华源可加速安装。
2. **官方 ms-swift 单卡 SFT 闭环已打通：** 启动 → loss → eval → checkpoint，约 1 分钟内完成 smoke test。
3. **复现资产已明确：** 不必记参数细节，保存 `args.json` + commit + 命令即可。
4. **5880 对本配置极度富裕：** 2.3 GiB 显存；放大模型/长度/多卡前应先对齐算法配置而非盲目加大。
5. **与生产差距主要在：** 算法改版源码、3 机分布式、真实数据 pipeline、监控指标定义（PPL）、生产级 checkpoint 策略。
6. **二开候选方向（待算法确认）：** 多机启动封装、训练/推理 args 一致性检查、指标标准化（含 PPL）、数据/val 快照可追溯。

---

## 5. 最终验收（本阶段 4 条对照）

| 验收条 | 当前 |
|--------|------|
| 3 机小规模跑通或失败可定位 | ⏳ 仅单卡跑通；分布式未做 |
| 流程记录齐全 | ✅ 本文档 + `args.json` + `logging.jsonl` |
| loss 与 PPL 有明确结论 | ✅ loss 有；PPL **无，待算法** |
| ≥1 个二开切入点被算法认可 | ⏳ 有候选，待步骤 7 |

---

## 6. ms-swift 数据格式详解

> 本节目的：方便后续对接算法数据或自定义数据时快速判断格式是否兼容、如何改写。

### 6.1 核心结论：所有格式在进 Trainer 前都必须转成 `messages`

这是框架的**硬约束**，由 `RowPreprocessor._check_messages()` 强制校验（`swift/dataset/preprocessor/core.py:64`）。
转换完成后，Template 还会再把 `messages` 编码为 `input_ids` + `labels`，其中 user 部分的 label 填 `-100`（不参与 loss），只有 assistant 的 token 才计算 loss。

```
原始数据（任意格式）
  └─ Preprocessor  →  messages [{"role","content"}, ...]
  └─ Template      →  input_ids / labels（user 部分 = -100）
  └─ HF Trainer（只看 input_ids / labels）
```

### 6.2 三条自动识别路径（AutoPreprocessor）

当数据集没有显式绑定处理器时（含大多数自定义本地文件），框架用 `AutoPreprocessor` 自动判断走哪条路径（`core.py:552`）：

| 路径 | 判断依据（字段名） | 处理器 |
|------|-------------------|--------|
| **A alpaca** | 同时有 `instruction` 和 `input` 列 | `AlpacaPreprocessor` |
| **B messages** | 有 `messages`、`conversations` 或 `conversation` 列 | `MessagesPreprocessor` |
| **C 兜底 QA** | 其余情况（有 `query`/`prompt`/`instruction` + `response`/`output` 等） | `ResponsePreprocessor` |

### 6.3 三种原始格式与样例

**格式 A — Alpaca（instruction / input / output）**

```json
{
  "instruction": "解释区块链在数据安全中的实用性。",
  "input": "",
  "output": "区块链技术通过其去中心化的结构..."
}
```

转换逻辑（`AlpacaPreprocessor.preprocess`，`core.py:420`）：
- `instruction` + `input` 拼接 → `query`（有 input 时用 `\n` 连接）
- `output` → `response`
- 再经 `ResponsePreprocessor` → `messages`

**格式 B — Messages / ShareGPT（openai 对话格式）**

```json
{
  "messages": [
    {"role": "user",      "content": "解释区块链在数据安全中的实用性。"},
    {"role": "assistant", "content": "区块链技术通过其去中心化的结构..."}
  ]
}
```

兼容变体：
- `conversations` / `conversation` 列名（自动映射为 `messages`）
- role 字段值支持 `human`/`gpt`/`bot` 等别名（自动标准化）
- 支持 ShareGPT 的 `{"human": "...", "gpt": "..."}` 结构（`sharegpt_to_messages`）
- 支持多轮对话（messages 数组包含多对 user/assistant）
- 支持 `system` 字段单独列（会插入为第一条 `role: system` 消息）

**格式 C — 简单 QA / 旧版 swift（query / response）**

```json
{"query": "解释区块链在数据安全中的实用性。", "response": "区块链技术..."}
```

`ResponsePreprocessor` 兼容的列名别名（`core.py:377`）：

| 标准字段 | 接受的别名 |
|----------|-----------|
| `query` | `prompt`、`input`、`instruction`、`question`、`problem` |
| `response` | `answer`、`output`、`targets`、`target`、`text`、`completion`、`content` |
| `system` | `system_prompt` |

### 6.4 本次训练实际走的路径

数据集 `AI-ModelScope/alpaca-gpt4-data-zh` 在源码注册时**显式绑定**了 `AlpacaZhPreprocessor`（路径 A 的子类），走的是：

```
{instruction, input, output}
  └─ AlpacaZhPreprocessor（中文 input 去掉"输入："前缀）
  └─ AlpacaPreprocessor（instruction+input → query, output → response）
  └─ ResponsePreprocessor（history_to_messages）
  └─ [{"role":"user","content":"..."}, {"role":"assistant","content":"..."}]
```

源码位置：`swift/dataset/dataset/llm.py:15`，`swift/dataset/preprocessor/core.py:409`。

### 6.5 自定义数据集接入方式

**最简单：直接用本地 jsonl，满足上述三种格式之一即可**

```bash
swift sft \
    --dataset /path/to/your/train.jsonl \
    ...
```

支持文件格式：`.jsonl`、`.json`、`.csv`、`.parquet`、`.arrow`（`loader.py:50`）。

**列名不对怎么办：用 `--columns` 重映射**

```bash
# 比如你的数据列名是 "question" 和 "answer"
swift sft \
    --dataset /path/to/data.jsonl \
    --columns '{"question":"query","answer":"response"}' \
    ...
```

**格式完全自定义：写处理器注册进去**

```python
from swift.dataset import register_dataset, DatasetMeta, RowPreprocessor

class MyPreprocessor(RowPreprocessor):
    def preprocess(self, row):
        # 把 row 转成含 messages 字段的 dict
        return {"messages": [
            {"role": "user",      "content": row["my_question"]},
            {"role": "assistant", "content": row["my_answer"]},
        ]}

register_dataset(DatasetMeta(
    dataset_path="/path/to/data.jsonl",
    preprocess_func=MyPreprocessor(),
))
```

### 6.6 算法侧实际数据格式（灵犀塔罗场景，已确认）

算法侧数据为**格式 B（messages 格式）**，直接兼容，无需任何转换。

#### 样本结构

每条样本是一个字典，`messages` 字段是一个**有序列表**，包含 3 种 role：

```
messages[0]   role: system      ← 必须第一条；每条样本只有一个
messages[1]   role: user        ← 用户提问；不参与 loss
messages[2]   role: assistant   ← 模型回答；参与 loss
messages[3]   role: user        ← 多轮时继续追加（可选）
messages[4]   role: assistant   ← 多轮回答；参与 loss（可选）
...
```

**约束（框架强制）：**
- `system` 只能出现一次，固定在 `messages[0]`
- `user` 和 `assistant` 必须严格交替，不能连续相同 role
- 最后一条必须是 `assistant`（否则无训练目标）
- 只有 `assistant` 的 token 计算 loss，`system` / `user` 的 token label 均填 `-100`

#### 单轮样本（3 条 message）

```json
{
  "messages": [
    {
      "role": "system",
      "content": "## Profile\n- Language: 中文\n- Description: 你是 心言集团开发的 灵犀，需要你扮演一个塔罗解读师..."
    },
    {
      "role": "user",
      "content": "用户的问题是："人生真的有意义吗？",用户抽到的塔罗牌：[权杖侍者 逆向，教皇 正向，月亮 正向],用户的提问时间：2025年09月24日:23时。"
    },
    {
      "role": "assistant",
      "content": "<解析>**权杖侍者逆位**：...。<结论>...，**建议你...**。"
    }
  ]
}
```

#### 多轮样本（1 + N×2 条 message，N 为轮数）

```json
{
  "messages": [
    {"role": "system",    "content": "## Profile\n..."},
    {"role": "user",      "content": "第一轮问题..."},
    {"role": "assistant", "content": "<解析>...第一轮回答..."},
    {"role": "user",      "content": "第二轮追问..."},
    {"role": "assistant", "content": "<解析>...第二轮回答..."}
  ]
}
```

单轮和多轮放在**同一个 jsonl 文件**，ms-swift 自动处理，无需区分。

#### loss 分配示意

```
[system tokens]    → label = -100  不参与 loss
[user tokens]      → label = -100  不参与 loss
[assistant tokens] → label = token_id  ✓ 参与 loss
[user tokens]      → label = -100  不参与 loss（多轮时）
[assistant tokens] → label = token_id  ✓ 参与 loss（多轮时）
```

#### 关于 max_length 的注意事项

system prompt 约 1500 字，加上 user 和 assistant，单条样本 token 数预计 **600–1500+**。
当前 smoke test 脚本中 `--max_length 512` **会截断大部分样本**，接入真实数据时需调整：

```bash
--max_length 2048    # 建议起点，视实际样本长度统计后调整
```

统计实际 token 长度的方法（接入数据前先跑）：

```python
from transformers import AutoTokenizer
import json

tokenizer = AutoTokenizer.from_pretrained("~/.cache/modelscope/hub/models/Qwen/Qwen3-0___6B")
lengths = []
with open("/path/to/train.jsonl") as f:
    for line in f:
        row = json.loads(line)
        text = "".join(m["content"] for m in row["messages"])
        lengths.append(len(tokenizer.encode(text)))

import statistics
print(f"中位数: {statistics.median(lengths):.0f}")
print(f"95分位: {sorted(lengths)[int(len(lengths)*0.95)]}")
print(f"最大值: {max(lengths)}")
```

#### 接入训练脚本（在 minimal_lora_sft.sh 基础上改动）

```bash
swift sft \
    --model Qwen/Qwen3-0.6B \
    --dataset /path/to/train.jsonl \
    --split_dataset_ratio 0.05 \       # 5% 作为 eval；或单独指定 val 文件
    --max_length 2048 \                # 根据实际 token 长度调整
    --tuner_type lora \
    --target_modules all-linear \
    --lora_rank 8 \
    --lora_alpha 32 \
    --torch_dtype bfloat16 \
    ...
```

若有单独 eval 文件：

```bash
    --dataset /path/to/train.jsonl \
    --val_dataset /path/to/val.jsonl \  # 替代 split_dataset_ratio
```

#### 快速验证数据格式是否正确

```bash
source .venv/bin/activate
python3 - <<'EOF'
from swift.dataset import load_dataset
train, val = load_dataset("/path/to/sample.jsonl", split_dataset_ratio=0.1)
print(f"train: {len(train)} 条，val: {len(val)} 条")
row = train[0]
print(f"字段: {list(row.keys())}")
for m in row["messages"]:
    print(f"  role={m['role']:12s} content={m['content'][:60]}...")
EOF
```

### 6.7 与算法对齐数据时要确认的项

| 项目 | 本地已知 | 待算法确认 |
|------|----------|-----------|
| 原始格式 | messages 格式（格式 B）| 是否有其他数据集用不同格式 |
| system prompt | 放在 `messages[0]`，每条样本都有 | 是否所有数据集都有 system |
| 单轮/多轮 | 两种都有，同一文件混用 | 多轮最多几轮；是否有轮次截断策略 |
| loss 分配 | 仅 assistant token 参与 | 是否有 `loss_scale` 加权（如 think token 降权）|
| 文件格式 | 待确认（jsonl / parquet）| 实际文件类型和路径 |
| max_length | 待统计（估计 600–1500+）| 生产训练使用的 max_length 值 |
| 数据量 | 待确认 | 总量；本地抽样建议 500–2000 条 |
| val 集 | 待确认 | 专门 eval 文件还是从 train split |
| 预处理脚本 | 未知 | 是否有算法侧数据清洗/转换脚本 |

---

## 7. 训练 Pipeline 与 Trainer 来源

### 7.1 Trainer 来源：HuggingFace Transformers 包装扩展

ms-swift 的 Trainer **不是从零实现的**，是在 HuggingFace Transformers 的 `Seq2SeqTrainer` / `Trainer` 上通过多继承 Mixin 方式扩展的。

文件头明确写明：`# Part of the implementation is borrowed from huggingface/transformers.`

**继承链（SFT 路径，`task_type=causal_lm`）：**

```
transformers.Seq2SeqTrainer          ← HuggingFace 原版（训练核心）
        ↑ 继承
swift.trainers.Seq2SeqTrainer        ← compute_loss / prediction_step 重写
        ↑ Mixin 注入（Python MRO 多继承）
SwiftMixin    (mixin.py:62)          ← 初始化、checkpoint、指标、callback、LoRA 加载
DataLoaderMixin (mixin.py:1168)      ← DataLoader 替换，支持 padding_free / sequence_parallel
```

源码位置：
- `swift/trainers/seq2seq_trainer.py:26` — `class Seq2SeqTrainer(SwiftMixin, DataLoaderMixin, HfSeq2SeqTrainer)`
- `swift/trainers/trainer.py:17` — `class Trainer(SwiftMixin, DataLoaderMixin, HfTrainer)`
- `swift/trainers/mixin.py:62` — `class SwiftMixin`
- `swift/trainers/trainer_factory.py:13` — 根据 `task_type` 路由到对应 Trainer

**任务类型 → Trainer 路由表（`trainer_factory.py:13`）：**

| task_type | Trainer |
|-----------|---------|
| `causal_lm`（SFT 走这里） | `swift.trainers.Seq2SeqTrainer` |
| `seq_cls` | `swift.trainers.Trainer` |
| `dpo` / `orpo` / `kto` | `swift.rlhf_trainers.*Trainer` |
| `grpo` | `swift.rlhf_trainers.GRPOTrainer` |
| `ppo` | `swift.rlhf_trainers.PPOTrainer` |

### 7.2 SFT 训练 Pipeline 全链路

```
swift sft 命令
    │
    ├─ [1] 参数解析
    │       TrainingArguments（继承 HF Seq2SeqTrainingArguments）
    │       + swift 自定义字段（lora_rank、template、deepspeed 等）
    │
    ├─ [2] 模型加载
    │       AutoModelForCausalLM（HuggingFace）
    │       → PeftModel / SwiftModel 包裹，注入 LoRA adapter
    │
    ├─ [3] 数据加载 & 预处理
    │       load_dataset()
    │       → Preprocessor（Alpaca / Messages / ResponsePreprocessor）
    │       → 所有格式统一转为 messages [{"role","content"},...]
    │
    ├─ [4] Template.encode()                    ← swift 独有，HF 没有这层
    │       messages → input_ids / labels
    │       user / system token → label = -100（不参与 loss）
    │       assistant token   → label = token_id（参与 loss）
    │       按模型 chat_template（如 qwen3）拼接特殊 token
    │       源码：swift/template/base.py:575
    │
    ├─ [5] DataLoader（DataLoaderMixin 替换 HF 原版）
    │       data_collator = template.data_collator  ← swift 自定义
    │       支持 padding_free、sequence_parallel、packing
    │       源码：swift/trainers/mixin.py:1168
    │
    ├─ [6] 训练循环（HF Trainer 原版）
    │       optimizer：adamw_torch_fused（默认）
    │       gradient_accumulation、bf16 混合精度
    │       gradient_checkpointing
    │
    ├─ [7] compute_loss（Seq2SeqTrainer 重写）
    │       标准 CE loss（-100 位置自动跳过）
    │       + loss_scale 加权（可选，token 级精细控制）
    │       + MoE router_aux_loss（若模型有 MoE 层）
    │       + token_acc 指标顺带计算
    │       源码：swift/trainers/seq2seq_trainer.py:123
    │
    ├─ [8] Eval（每 eval_steps 触发）
    │       默认：eval_loss + eval_token_acc
    │       可选：predict_with_generate（真正做生成推理评估）
    │
    ├─ [9] Checkpoint（HF 原版 + swift 扩展）
    │       LoRA：adapter_model.safetensors + adapter_config.json
    │       全参：model.safetensors（完整权重）
    │       元信息：args.json / trainer_state.json
    │       Resume 用：optimizer.pt / scheduler.pt / rng_state.pth
    │
    └─ [10] 日志输出
            终端（tqdm）
            logging.jsonl（逐步指标）
            TensorBoard runs/
            images/（自动生成曲线图）
```

### 7.3 哪些是 HF 原版，哪些是 swift 新增

| 环节 | 来源 | 备注 |
|------|------|------|
| 训练循环（optimizer、梯度累积、混合精度） | **HF Transformers** | 完全复用 |
| DeepSpeed / FSDP 集成 | **HF Transformers** | swift 透传参数 |
| Checkpoint 保存与 resume | **HF** 为主 | swift 加了 ModelScope hub 上传 |
| 模型加载（AutoModel） | **HF Transformers** | swift 加了模型注册、model_info |
| LoRA / QLoRA / DoRA 等 | **PEFT 库** | swift 在上面加了 SwiftModel 扩展 |
| **Template（messages → tokens）** | **swift 独有** | HF 无此层，这是 swift 核心贡献 |
| **data_collator（对话格式）** | **swift 独有** | HF 的 collator 不处理对话格式 |
| **loss_scale / MoE aux_loss** | **swift 新增** | HF 无此逻辑 |
| **padding_free / sequence_parallel DataLoader** | **swift 新增** | HF 不支持 |
| token_acc 指标 | **swift 新增** | HF 只有 loss |

### 7.4 二开切入点定位指南

| 想改什么 | 看哪个文件 |
|----------|-----------|
| 训练循环、optimizer、梯度逻辑 | HF Transformers 源码（不在 swift 里）|
| 对话格式 → token 序列的拼接逻辑 | `swift/template/base.py` |
| loss 计算（加权、MoE、loss_scale） | `swift/trainers/seq2seq_trainer.py` |
| LoRA adapter 注入与保存 | `swift/trainers/mixin.py`（SwiftMixin）|
| DataLoader（采样、padding、packing） | `swift/trainers/mixin.py`（DataLoaderMixin）|
| 数据格式识别与转换 | `swift/dataset/preprocessor/core.py` |
| 指标（token_acc、PPL 等） | `swift/metrics/` |
| Callback（logging、checkpoint 触发）| `swift/callbacks/` |

---

## 8. 与算法侧 Full-Param SFT 的 Diff

> 本节记录本次预跑（LoRA 单卡）与算法侧全参 SFT 之间的已知差距，用于步骤 6 校对。

### 8.1 最核心差异：微调方式

| 项目 | 本次预跑 | 算法侧（推测） | 对应步骤 |
|------|----------|--------------|---------|
| **tuner_type** | `lora` | `full`（全参训练） | 步骤 4 缩小配置 |
| **可训练参数量** | 5.05M / 601M（0.84%） | 100%（所有参数） | — |
| **checkpoint 内容** | `adapter_model.safetensors`（20MB） | `model-0000X-of-XXXX.safetensors`（分片，数 GB）| 步骤 5 |
| **推理方式** | 基座 + adapter 同时需要 | checkpoint 目录直接用 | — |
| **学习率** | 1e-4（LoRA 典型值） | 1e-5 ~ 2e-5（全参更低）| 步骤 4 |

从 LoRA 切换到全参，脚本改动：

```bash
# 删除 LoRA 相关参数，调低学习率
--tuner_type full          # lora → full
--learning_rate 1e-5       # 1e-4 → 1e-5
--warmup_ratio 0.05        # 建议加上
# 以下三行删除：
# --lora_rank 8
# --lora_alpha 32
# --target_modules all-linear
```

### 8.2 分布式训练（本次未做）

| 项目 | 本次预跑 | 3 机 Full-Param 目标 |
|------|----------|---------------------|
| 机器数 | 1 台 | 3 台（5880） |
| GPU 数 | 1 卡 | 3 × N 卡 |
| DeepSpeed | 无 | ZeRO-2 或 ZeRO-3（全参必须分显存） |
| 启动方式 | `swift sft` 直接 | `NNODES=3 NODE_RANK=X MASTER_ADDR=... swift sft` |
| global batch | 1×4 = 4 | `per_device × grad_accum × NPROC × NNODES` |

3 机全参启动参考（每台机器仅 `NODE_RANK` 和 `MASTER_ADDR` 不同）：

```bash
# node0（rank 0）
NNODES=3 NODE_RANK=0 \
MASTER_ADDR=<node0_ip> MASTER_PORT=29500 \
NPROC_PER_NODE=8 CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \
swift sft \
    --model <model_path> \
    --tuner_type full \
    --deepspeed zero2 \
    --dataset /path/to/train.jsonl \
    --max_length 2048 \
    --per_device_train_batch_size 1 \
    --gradient_accumulation_steps 4 \
    --learning_rate 1e-5 \
    --warmup_ratio 0.05 \
    --output_dir output/full-sft-3node
```

### 8.3 Checkpoint 结构差异

| 项目 | LoRA checkpoint | Full-Param checkpoint |
|------|----------------|-----------------------|
| 模型文件 | `adapter_model.safetensors` | `model-00001-of-XXXX.safetensors`（分片）|
| 配置文件 | `adapter_config.json` | `config.json`（原模型配置） |
| 推理命令 | `--adapters output/.../checkpoint-N` | `--model output/.../checkpoint-N` |
| 单个 checkpoint 磁盘占用 | ~20MB（adapter 部分）| 与模型等大（数 GB ~ 数十 GB） |
| `save_total_limit` 管理磁盘 | 影响小 | **必须认真规划**，防止磁盘打满 |

### 8.4 超参数对照

| 参数 | 本次（LoRA smoke test） | Full-Param 典型值 | 说明 |
|------|------------------------|------------------|------|
| `learning_rate` | 1e-4 | 1e-5 ~ 2e-5 | 全参训练更保守 |
| `warmup_ratio` | 无（0） | 0.03 ~ 0.05 | 全参建议加 warmup |
| `max_length` | 512（严重截断） | 2048 ~ 8192 | 按实际样本长度统计后设定 |
| `gradient_accumulation_steps` | 4 | 按 global batch 目标反算 | 多机时每机各自的 accum 步数要除以机器数 |
| `per_device_train_batch_size` | 1 | 1（全参显存紧张） | 视模型大小和 GPU 显存决定 |
| `save_total_limit` | 1 | 2 ~ 3 | 全参磁盘大，不宜存太多 |

### 8.5 待向算法确认的 diff 项

| 项目 | 确认内容 | 校对五态 |
|------|---------|---------|
| ms-swift 源码版本 | 公式 main vs 算法 fork，commit 和 diff | 待确认 |
| DeepSpeed 配置 | zero2 / zero3 / offload；是否用自定义 ds_config.json | 待确认 |
| packing | 是否启用 `--packing true`（长序列效率优化） | 待确认 |
| eval 方式 | `eval_loss` 还是 `predict_with_generate` | 待确认 |
| loss_scale | 是否对 think token / system token 加权 | 待确认 |
| 数据采样策略 | 是否按长度排序、curriculum、多数据集混合比例 | 待确认 |
| gradient_checkpointing | 当前默认开启，生产是否一致 | 待确认 |

---

## 9. 附录：关键日志片段

```
Train: 12/12 steps, train_loss=1.673, runtime=7.2s
eval_loss=1.653, eval_token_acc=0.621
last_model_checkpoint: .../checkpoint-12
best_model_checkpoint: .../checkpoint-12
train_dataset: size=45, val_dataset: size=5
model: PeftModel 601M params, 5.05M trainable (0.84%)
```

---

*文档生成：2026-05-20，对应预跑 run `v0-20260520-164707`。*
