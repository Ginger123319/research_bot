# SFT 细节了解 Q\&amp;A to infra

最近在做训练框架二次开发的规划，想先把你们 SFT 现在的实际工作方式摸清楚。下面是想跟你们聊的几块内容

---

## **1\. SFT 工作流主干**

- 一次完整的 SFT 任务从立项到上线，大致经过哪几个环节

```Nginx
需求定义 → 数据工程 → 模型选型/训练配置 → 训练执行 → 评估验证 → 部署上线
```

- 每个环节用什么工具或框架（LLaMA\-Factory / SWIFT / Megatron / 自研脚本 / \.\.\.）

```Nginx
# 用的都是ms-swift

**小规模快速实验**：SWIFT，适合 70B 以下
**大规模正式训练**：Megatron-LM 70B以上基本都是这条路
```

- 哪些是现成框架直接用、哪些是手工或临时脚本拼起来的

```Nginx

```

## **2\. 痛点和 \&\#34;想做但做不到\&\#34; 的事**

- 流程里最经常失败 / 最浪费时间 / 最经常需要改代码的环节

```Nginx
多机多卡训练跑到60%某张卡挂了，理想情况下应该自动从最近checkpoint恢复，
实际情况：无法自动断点续讯， 整个job挂掉 需要 手动排查是哪台机器
```

- \&\#34;我想做 X 但现在做起来很费劲\&\#34; 的清单

```Nginx
实验追踪和复现：监控用 W&B / TensorBoard
多任务loss加权，框架不原生支持，要改训练循环
在线评估in-the-loop，训完自动跑自动化评估拿到结果
模型量化（sft后的大模型，量化后尽量减少精度损失）
模型精度转换（kimi-2.6开源的精度为int4，转为bf16或fp16）
```

## **3\. 资源和规模**

- 现在主要训练的模型规模（7B / 13B / 70B / MoE？）

```Nginx
分类模型：3-7B dense模型
工具模型：32b-72b dense模型 最近在用qwen3.5-122B-A10B或qwen3-235B-A22B
```

- 未来有没有计划要训的、规模和现在差异比较大的模型

```Nginx
最近在利用swift和megatron探索lora训练kimi-2.5和kimi-2.6
```

- 现有 GPU 资源（型号、卡数、单机或多机）

```Nginx
阿里云 8台H200（141G x 8 GPUs）
```

- 单次 SFT 任务的典型时长 / GPU 卡时

```Nginx
根据数据量和batch
```

- 现在训练任务最让你们难受的是什么——显存（动不动 OOM）、速度（一轮跑太久），还是人力（手工活太多）

```Nginx
故障恢复
显存限制（比如235b模型，最大长度不能开太高）
```

## **4\. 微调方法**

- LoRA / QLoRA / 全参微调各自的使用比例

- 选 LoRA 还是全参，决策依据是什么（精度差距 / 显存逼的 / 速度需要？）

## **5\. 评估 \&amp; checkpoint（简单聊聊就行）**

- 评估流程长什么样、是否和训练 in\-the\-loop

```Nginx
┌─────────────────────────────┐
                    │      评估 Pipeline           │
                    │                             │
训练产出             │  ① 自动指标评估              │
checkpoint ──────→  │     - Benchmark 跑分         │
                    │       (MMLU/GSM8K/HumanEval  │
                    │        /C-Eval/自建测试集)    │
                    │     - 工具：OpenCompass /      │
                    │       evalscope             │
                    │                             │
                    │  ② 生成式评估                │
                    │     - 用GPT-4/Claude做      │
                    │       pairwise comparison    │
                    │     - MT-Bench / AlpacaEval  │
                    │     - 自建场景化 test cases   │
                    │                             │
                    │  ③ 人工评测                  │
                    │     - 标注团队side-by-side    │
                    │     - 产品验收                │
                    └─────────────────────────────┘

```

- checkpoint 多大、多久产一次、怎么管理和复用





---

2026\-05\-25

# **SFT 复现——需要算法提供的材料**

目标：在本地 3 台 5880 上复现 Megatron SFT 全流程（MoE 全参）。



## **需要的文件 / 代码**

|**num**|**内容**|**说明**|**回复**|**备注**|
|---|---|---|---|---|
|1|ms\-swift fork 仓库地址 \+ branch \+ commit|用于克隆和安装|```Shell<br># Github：       <br>git clone -b main https://github.com/modelscope/ms-swift.git<br># 镜像：<br>modelscope-registry.cn-beijing.cr.aliyuncs.com/modelscope-repo/modelscope:ubuntu22.04-cuda13.0.3-py312-torch2.11.0-vllm0.20.1-modelscope1.36.3-swift4.2.0<br>```|通常用main，目前使用的是4\.2\.0版本|
|2|HF → Megatron 转换脚本 / 命令|含 TP/PP/EP 参数；附转换后目录结构样例|```Bash<br>MODEL_NAME=Qwen3.5-35B-A3B<br>MODEL_PATH=/xxx/${MODEL_NAME}<br>output_dir=/xxx/${MODEL_NAME}-mcore<br>echo ""模型${MODEL_NAME}""<br>echo ""保存路径为 ${output_dir}""<br>CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \<br>swift export \<br>    --model $MODEL_PATH \<br>    --to_mcore true \<br>    --torch_dtype bfloat16 \<br>    --output_dir $output_dir \<br>    --test_convert_precision true<br>```|更多[导出参数](https://swift.readthedocs.io/zh-cn/latest/Megatron-SWIFT/Command-line-parameters.html#id3)|
|3|完整训练启动命令|含多机参数（NNODES / MASTER\_ADDR / NODE\_RANK）；脱敏即可|```Shell<br># 设置自定义 ms-swift 路径<br>export PYTHONPATH="/xxx/train/ms-swift-4.2.0:$PYTHONPATH"<br># 验证是否为指定路径<br>python -c "import swift; print(swift.__file__)"<br>project=bazi-merge<br>verson=v1<br>DATE=0524<br>max_length=12288<br>MODEL_NAME=Qwen3.5-122B-A10B<br>output_dir=/xxx/${project}/${verson}_${DATE}_${MODEL_NAME}_${max_length}<br>export PYTORCH_CUDA_ALLOC_CONF='expandable_segments:True'<br>PYTORCH_CUDA_ALLOC_CONF='expandable_segments:True' \<br>NNODES=$WORLD_SIZE \<br>NODE_RANK=$RANK \<br>megatron sft \<br>    --model /xxx/Qwen3.5-122B-A10B \<br>    --dataset /xx/train_data.jsonl \<br>     --save_safetensors true \<br>    --split_dataset_ratio 0 \<br>    --agent_template hermes \<br>    --add_non_thinking_prefix true \<br>    --loss_scale ignore_empty_think \<br>    --dataset_shuffle false \<br>    --tuner_type full \<br>    --pipeline_model_parallel_size 1 \<br>    --tensor_model_parallel_size 2 \<br>    --expert_model_parallel_size 8 \<br>    --sequence_parallel true \<br>    --moe_permute_fusion true \<br>    --moe_grouped_gemm true \<br>    --moe_shared_expert_overlap true \<br>    --moe_aux_loss_coeff 1e-4 \<br>    --micro_batch_size 1 \<br>    --global_batch_size 512 \<br>    --recompute_granularity full \<br>    --recompute_method uniform \<br>    --recompute_num_layers 1 \<br>    --overlap_grad_reduce true \<br>    --overlap_param_gather true \<br>    --num_train_epochs 1 \<br>    --finetune true \<br>    --cross_entropy_loss_fusion true \<br>    --lr 2e-5 \<br>    --lr_warmup_fraction 0.03 \<br>    --lr_decay_style cosine \<br>    --min_lr 2e-6 \<br>    --output_dir ${output_dir} \<br>    --eval_steps 300 \<br>    --save_steps 300 \<br>    --max_length $max_length \<br>    --dataloader_num_workers 8 \<br>    --dataset_num_proc 16 \<br>    --no_save_optim true \<br>    --no_save_rng true \<br>    --attention_backend flash \<br>    --padding_free false \<br>    --seed 42<br>```|[更多参数](https://swift.readthedocs.io/zh-cn/latest/Megatron-SWIFT/Command-line-parameters.html#megatron)|
|4|Megatron → HF 转换脚本 / 命令|附转换后目录结构样例|```Bash<br>MODEL_NAME=Qwen3-Next-80B-A3B-Instruct<br>MODEL_PATH=/xxx/train_models/v1-20260114-144402<br>output_dir=/xxx/Megatron2HF/${MODEL_NAME}-v1<br>echo ""待转格式 模型路径 ${MODEL_PATH}""<br>echo ""保存路径为 ${output_dir}""<br>CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \<br>swift export \<br>    --mcore_model $MODEL_PATH \<br>    --to_hf true \<br>    --torch_dtype bfloat16 \<br>    --output_dir $output_dir \<br>    --test_convert_precision true<br>```||
|5|脱敏小数据集（train \+ eval，几百条）|jsonl/parquet 均可；附 schema \+ 1–2 条样例|AI\-ModelScope/alpaca\-gpt4\-data\-zh\#500|开源数据集，可直接使用|
|6|如何在框架中自定义测试集做验证|需要插入或者修改那些代码，在哪里注入|||
|7|benchmark 离线测试脚本入口 \+ 运行命令||evalscope、opencompass||



## **需要确认的问题**

**数据**

```Markdown
1. 文件字段名是什么（messages / conversations / ...）
    ShareGPT
    OpenAI ChatML

2. max_length 是多少，超长截断还是丢弃
    不固定，超长截断

3. 有没有loss_scale加权（think token / system token），配置在哪
    标准SFT：只对assistant token算loss（user/system/tool通常mask为0）
    Think / reasoning：reasoning 参与loss；是否对think token降权（如 loss_scale=0.1）

```

## 数据格式

```JSON
{"system": "You are a helpful assistant.", "instruction": "中国人在美国只拿绿卡不入籍，还能保留中国国内的养老医保待遇吗", "input": "", "output": "根据中国政策，中国公民在申请外国国籍时需要注销中国国籍。因此，如果中国人在美国只拿绿卡不入籍，就仍然保留中国国籍，他们就有可能继续享受中国国内的养老医保待遇。但具体情况需要参考当地的相关政策规定。建议咨询当地的中国驻外使领馆或相关部门。", "history": []}
```

```SQL
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





**模型**

```Markdown
1. 生产用的是哪个模型（122B / 235B），架构确认是 MoE + MLA 吗
    - 种类很多不固定

2. 本地复现建议用哪个小基座（1B–7B）
    - 建议用小模型复现一下，moe可以考虑qwen3.5-30b-a3b，dense用7b小模型

3. 需不需要手动register_model，怎么验证生效
    - 标准HF模型（config.json 有正确model_type）不需要手动注册
    - 参考ms-swift官方文档https://swift.readthedocs.io/zh-cn/latest/Megatron-SWIFT/Custom-Model.html

4. MLA权重映射有没有特殊处理，代码在哪
    
```



**训练配置**

- 122B / 235B 的典型并行度：TP / PP / EP / DP 各是多少

```Markdown
TP = 2
PP = 1
EP = 8
```

- 这些并行参数和 batch size 怎么算的（举个例子）

```Markdown
总卡数 = TP × PP × EP × DP
global_batch_size = micro_batch_size × DP × gradient_accumulation_steps
```

**监控与稳定性**

- 目前使用的主要有哪些监控指标

```Markdown
1. loss (train / eval): 主曲线，smoothing=0.99
2. learning_rate: 确认 warmup + cosine decay正确
3. grad_norm: 梯度范数，spike预警
4. tokens_per_second: 吞吐，判断是否有straggler
5. gpu_memory_allocated: 显存水位
6. moe_aux_loss: router 辅助损失（MoE 特有，防止 expert 坍塌）
7. expert_load_balance: 各 expert token 分配比例
8. load_balancing_loss ：专家利用率是否均匀（某些专家被过度使用）
```

- 怎么判断所有 rank 都正常进了训练循环

```Shell
## 查看日志
grep "training step 1" logs/rank_*.log | wc -l  *# 应等于总rank数*
```

- loss NaN / spike 有没有历史案例和处理方法

|**现象**|**可能原因**|**处理方法**|**备注**|
|---|---|---|---|
|**突然NaN**|数据异常（空样本/超长）|回退checkpoint \+ 跳过问题数据||
|**周期性spike**|Router不稳定（MoE）|增大moe\_aux\_loss\_coeff（如 0\.01→0\.1）||
|**训练中期突发**|梯度爆炸|加 \-\-clip\-grad 1\.0，检查是否某层grad异常大||

- 断点续训有没有不稳定的场景，有没有 workaround

```Shell
--no_save_optim false \
--no_save_rng false \
```











