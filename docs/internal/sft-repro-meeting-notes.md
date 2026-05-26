# SFT 复现对齐记录

> 来源：算法侧《SFT 细节了解 Q&A to infra》（`docs/results/SFT 细节了解 Q&A to infra.md`，2026-05-25）
> 目标：在本地 3 台 5880 上复现 Megatron SFT 全流程（MoE 全参）。

---

## 源码

- fork 仓库地址 / branch / commit：
  - 上游：`https://github.com/modelscope/ms-swift.git`，branch `main`
  - 当前生产用版本：**ms-swift 4.2.0**（通常跟 main，按需 pin 版本）
- 安装命令：
  - 推荐直接用算法侧官方镜像：
  `modelscope-registry.cn-beijing.cr.aliyuncs.com/modelscope-repo/modelscope:ubuntu22.04-cuda13.0.3-py312-torch2.11.0-vllm0.20.1-modelscope1.36.3-swift4.2.0`
  - 如需用本地 fork 覆盖镜像内的 swift：
    ```bash
    export PYTHONPATH="/xxx/train/ms-swift-4.2.0:$PYTHONPATH"
    python -c "import swift; print(swift.__file__)"   # 验证生效
    ```
- 相对官方 main 的改动（模型注册 / Megatron 适配 / 其他）：
  - 标准 HF 模型（`config.json` 有正确 `model_type`）**不需要手动注册**
  - 自定义模型参考：[https://swift.readthedocs.io/zh-cn/latest/Megatron-SWIFT/Custom-Model.html](https://swift.readthedocs.io/zh-cn/latest/Megatron-SWIFT/Custom-Model.html)
  - 其他业务改动：**暂无**

---

## 数据

- 数据来源，处理脚本做了什么：业务数据脱敏后用，复现可直接用开源数据集 `AI-ModelScope/alpaca-gpt4-data-zh#500`

文件格式 / 字段名：支持ShareGPT / Alpaca 两种

```markdown
{"system": "You are a helpful assistant.", "instruction": "中国人在美国只拿绿卡不入籍，还能保留中国国内的养老医保待遇吗", "input": "", "output": "根据中国政策，中国公民在申请外国国籍时需要注销中国国籍。因此，如果中国人在美国只拿绿卡不入籍，就仍然保留中国国籍，他们就有可能继续享受中国国内的养老医保待遇。但具体情况需要参考当地的相关政策规定。建议咨询当地的中国驻外使领馆或相关部门。", "history": []}

{
  "conversations": [
    {
      "from": "human",
      "value": "Edit the following sentence to make it more concise: \"He had a really bad headache, it was very intense.\""
    },
    {
      "from": "gpt",
      "value": "He had an intense headache."
    }
  ]
}
```

- 数据量（train / eval）：脱敏小数据集**几百条**起（脱敏样例：见 alpaca-gpt4-data-zh#500）
- max_length / 超长处理：**不固定**，按任务调整；超长**截断**（不丢弃）。当前 122B 配置示例 `max_length=12288`
- loss_scale 加权（有/无），配置位置：
  - **标准 SFT**：只对 assistant token 算 loss，user/system/tool 通常 mask 为 0
  - **Think / Reasoning 模型**：reasoning 参与 loss，可对 think token 降权（如 `loss_scale=0.1`）
  - 当前生产命令使用：`--loss_scale ignore_empty_think`

---

## 模型

- 生产模型（122B / 235B，MoE+MLA / Dense）：
  - 分类模型：3–7B Dense
  - 工具模型：32B–72B Dense
  - 最近主力：**qwen3.5-122B-A10B**、**qwen3-235B-A22B**（MoE）
  - 在探索：用 LoRA 跑 Kimi-2.5 / Kimi-2.6
- 本地复现推荐小基座：
  - **MoE**：`qwen3.5-30b-a3b`
  - **Dense**：7B 量级小模型
- 需要手动 register_model（是/否），验证方法：
  - **否**，标准 HF 模型直接识别 `config.json` 的 `model_type`
  - 非标准模型按 ms-swift 自定义模型文档接入
- HF → Megatron 转换命令 / 脚本：最新版本的ms-swift内部已经支持了这个转换，用户不感知了
  ```bash
  MODEL_NAME=Qwen3.5-35B-A3B
  MODEL_PATH=/xxx/${MODEL_NAME}
  output_dir=/xxx/${MODEL_NAME}-mcore
  CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \
  swift export \
      --model $MODEL_PATH \
      --to_mcore true \
      --torch_dtype bfloat16 \
      --output_dir $output_dir \
      --test_convert_precision true
  ```
  参考：<https://swift.readthedocs.io/zh-cn/latest/Megatron-SWIFT/Command-line-parameters.html#id3>
- 转换后目录结构：**待补充**（请算法侧贴一份 `ls` 样例）
- MLA 权重映射特殊处理（有/无），暂无

---

## 训练配置

- 并行度（122B，qwen3.5-122B-A10B）：**TP=2  PP=1  EP=8  DP=由总卡数推出**
- 并行度（235B，qwen3-235B-A22B）：**待补充**（Q&A 仅给出 122B 的典型值）
- batch size 计算方法：
  - `总卡数 = TP × PP × EP × DP`
  - `global_batch_size = micro_batch_size × DP × gradient_accumulation_steps`
  - 当前 122B 示例：`micro_batch_size=1`，`global_batch_size=512`
- 完整启动命令：算法侧 Q&A 文档「需求文件 / 代码」第 3 行已给出，关键参数摘录：
  ```bash
  export PYTHONPATH="/xxx/train/ms-swift-4.2.0:$PYTHONPATH"
  export PYTORCH_CUDA_ALLOC_CONF='expandable_segments:True'

  NNODES=$WORLD_SIZE NODE_RANK=$RANK \
  megatron sft \
      --model /xxx/Qwen3.5-122B-A10B \
      --dataset /xxx/train_data.jsonl \
      --tuner_type full \
      --tensor_model_parallel_size 2 \
      --pipeline_model_parallel_size 1 \
      --expert_model_parallel_size 8 \
      --sequence_parallel true \
      --moe_permute_fusion true \
      --moe_grouped_gemm true \
      --moe_shared_expert_overlap true \
      --moe_aux_loss_coeff 1e-4 \
      --micro_batch_size 1 \
      --global_batch_size 512 \
      --recompute_granularity full --recompute_method uniform --recompute_num_layers 1 \
      --overlap_grad_reduce true --overlap_param_gather true \
      --lr 2e-5 --lr_warmup_fraction 0.03 --lr_decay_style cosine --min_lr 2e-6 \
      --max_length 12288 \
      --eval_steps 300 --save_steps 300 \
      --attention_backend flash --padding_free false \
      --seed 42
  ```
  完整版见 `docs/results/SFT 细节了解 Q&A to infra.md`，多机变量：`NNODES / NODE_RANK / MASTER_ADDR`

---

## 监控

- 日志格式 / `logging.jsonl` 位置：**待补充**（Q&A 未直接说明，仅提到 `logs/rank_*.log`）
- 监控工具 / 入口：**W&B / TensorBoard**（实验追踪自评为痛点之一，仍想做但难度大）
- 打出来的指标：
  1. `loss`（train / eval，smoothing=0.99）
  2. `learning_rate`（验证 warmup + cosine decay）
  3. `grad_norm`（spike 预警）
  4. `tokens_per_second`（吞吐 / straggler 检测）
  5. `gpu_memory_allocated`
  6. `moe_aux_loss`（防止 expert 坍塌）
  7. `expert_load_balance`（各 expert token 分配比例）
  8. `load_balancing_loss`（专家利用率均匀性）
- 判断所有 rank 正常进训练循环的方法：
  ```bash
  grep "training step 1" logs/rank_*.log | wc -l   # 应等于总 rank 数
  ```
- loss NaN / spike 处理流程 / 历史案例：

  | 现象        | 可能原因            | 处理方法                                  |
  | --------- | --------------- | ------------------------------------- |
  | 突然 NaN    | 数据异常（空样本 / 超长）  | 回退 checkpoint + 跳过问题数据                |
  | 周期性 spike | Router 不稳定（MoE） | 增大 `moe_aux_loss_coeff`（如 0.01 → 0.1） |
  | 训练中期突发    | 梯度爆炸            | 加 `--clip-grad 1.0`，检查是否某层 grad 异常大   |


---

## Checkpoint

- 目录结构（`iter_XXXXXXXX/` 里面）：**待补充**
- 保存频率 / 保留规则：当前 `--save_steps 300`，保留规则**待补充**
- 断点续训命令：**痛点 — 当前没法自动恢复**
  - 现状：多机多卡训练跑到 60% 时单卡挂掉，整 job 挂掉，需要手动定位机器
  - 理想：从最近 checkpoint 自动恢复
- 不稳定场景 / workaround：
  - 默认配置 `--no_save_optim true --no_save_rng true` 是为了省空间，但断点续训不稳；
  - 续训时显式打开：
    ```bash
    --no_save_optim false \
    --no_save_rng false
    ```

---

## Megatron → HF 转换

- 转换命令 / 脚本：ms-swift老版本需要按照如下的脚本进行转换
  ```bash
  MODEL_NAME=Qwen3-Next-80B-A3B-Instruct
  MODEL_PATH=/xxx/train_models/v1-20260114-144402
  output_dir=/xxx/Megatron2HF/${MODEL_NAME}-v1
  CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \
  swift export \
      --mcore_model $MODEL_PATH \
      --to_hf true \
      --torch_dtype bfloat16 \
      --output_dir $output_dir \
      --test_convert_precision true
  ```

---

## 评估

- eval 频率 / 指标：训练侧 `--eval_steps 300`；评估 pipeline 三层：
  1. **自动指标**：MMLU / GSM8K / HumanEval / C-Eval / 自建测试集（工具：**OpenCompass / evalscope**）
  2. **生成式评估**：GPT-4 / Claude 做 pairwise，MT-Bench、AlpacaEval、自建场景化 test cases
  3. **人工评测**：标注团队 side-by-side、产品验收
- 加载格式（HF / Megatron）：Megatron 训完先转回 **HF**，再跑 benchmark
- SFT「有效」的判断标准：**待补充**（目前主要看 benchmark + 生成式评估 + 人工，缺一个明确 go/no-go 标准）
- benchmark 离线测试脚本：开源的**evalscope** 和 **opencompass**

---

