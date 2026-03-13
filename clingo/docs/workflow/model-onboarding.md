# 新模型接入 SOP

> 模型部署迁移评估标准操作流程  
> 基于 xinghan-ziwei-32b-v1 全流程实践提炼  
> 更新：2026-03-11

---

## 总览

```
Step 0  信息收集 & 准入确认
    ↓
Step 1  本地容器部署 & 健康检查
    ↓
Step 2  服务探测（仅在无业务数据时）← 可选
    ↓
Step 3  数据处理（JSONL/ShareGPT → 压测 CSV）
    ↓
Step 4  远端服务连通性验证（k8s 平台 endpoint）
    ↓
Step 5  Benchmark 执行（QPS 扫描 / 压力测试）
    ↓
Step 6  结果分析 & 报告归档
```

---

## Step 0：信息收集 & 准入确认

在开始前，从业务方或 README 中确认：

| 项目 | 说明 | 来源 |
|------|------|------|
| 模型名称 / 版本 | e.g. `xinghan-ziwei-32b-v1` | 迁移清单（`README.md`）|
| 模型路径 | e.g. `/mnt/ai-llm/<model-name>` | 运维确认 |
| 镜像 | e.g. `reg.xxwolo.com/master/sglang:v0.4.1.post4` | 运维确认 |
| 可用 GPU | 数量、卡号、互联方式（NVLink/PCIe） | `nvidia-smi topo -m` |
| TP 配置建议 | NVLink → TP=N；PCIe L20 → TP=1×DP=N | 根据拓扑判断 |
| 业务数据 | JSONL 日志路径（`/mnt/ai-infra/datasets/`）或无 | 业务方 |
| 平台服务 URL | k8s 部署后的 endpoint | 平台部署后获取 |
| 业务联系人 | 算法负责人，用于确认模型用途 | 迁移清单 |

---

## Step 1：本地容器部署

**参考目录**：`scripts/deploy/`

### 1.1 写启动脚本

复制现有脚本改参数：

```bash
cp scripts/deploy/start_ziwei_32b.sh scripts/deploy/start_<model-name>.sh
```

关键参数：

```bash
CONTAINER_NAME="<model-name>-server"
IMAGE="reg.xxwolo.com/ai/lmsysorg-sglang:latest"
MODEL_PATH="/mnt/ai-llm/<model-name>"
PORT=<分配端口>
BASE_GPU_ID=<起始GPU卡号>     # 避免与已运行容器冲突
TP_SIZE=<TP数>
```

> **注意**：PCIe L20 机器建议用 `TP=1`，多实例 DP，避免 AllReduce 通信瓶颈。  
> `--base-gpu-id` 解决多容器 GPU 内存分配不均问题。

### 1.2 执行部署

```bash
bash scripts/deploy/start_<model-name>.sh
```

### 1.3 健康检查

```bash
curl http://localhost:<PORT>/health          # 应返回 {"status": "ok"} 或 200
docker logs -f <container-name>             # 观察启动日志
```

等待服务就绪标志：日志出现 `The server is fired up and ready to roll!`

---

## Step 2：服务探测（可选）

**触发条件**：业务方未提供数据，且模型用途不明确时。

**目的**：用探针 query 反向推断模型在业务场景中的能力类型（对话 / 分类 / 安全拦截 / 其他）。

**参考目录**：`scripts/probe/`

```bash
source .venv/bin/activate
python scripts/probe/probe_models.py          # 本地双模型探测
python scripts/probe/probe_<model-name>.py    # 针对新模型的定制探测
```

探测脚本标准节结构：

| 节 | 目的 |
|----|------|
| 基础功能验证 | 确认服务可正常响应 |
| 能力边界测试 | 了解模型处理哪类输入 |
| 拒绝 / 放行行为 | 对安全拦截类模型统计准确率 |
| 延迟基准 | 10 条 query，输出 avg / P50 / P90 |
| 汇总报告 | 综合结论 |

> 遇到输出循环重复：加 `"repetition_penalty": 1.1` 到请求参数。

---

## Step 3：数据处理

**参考 Skill**：`.cursor/skills/traffic-dataset-prep/SKILL.md`

### 情况 A：业务方提供线上 JSONL 日志

数据路径规范：`/mnt/ai-infra/datasets/<model-name>/`

**每个模型新建专属脚本**（复制现有的改参数，不共用）：

```bash
cp scripts/data/process_ziwei_full.py scripts/data/process_<model-name>_full.py
# 修改脚本顶部的配置块：JSONL_FILE / OUTPUT_DIR / MODEL_NAME / MODEL_LIST / TARGET_PEAK / PEAK_WINDOWS
```

脚本开头注明遵循 Skill：

```python
"""
<model-name> 完整数据处理脚本
遵循 traffic-dataset-prep SKILL 5步管道：
  步骤1: DataConverter → _all.csv
  步骤2: DataSampler → 峰值窗口采样
  步骤3: 时间戳拼接 → 消除段间 >5min 大间隔
  步骤4: DataInterpolator → 泊松插值放大 RPM
  步骤5: 脏数据过滤 → 剔除 content 为 list 的行
"""
```

```bash
source .venv/bin/activate
python scripts/data/process_<model-name>_full.py
```

关键决策点：

| 决策 | 依据 | 参考值 |
|------|------|--------|
| `MODEL_LIST` 别名 | JSONL 中 `extra_data.ai_info.model` 的实际写法 | **⚠️ 必须包含所有别名**（含中文），否则丢失大量数据 |
| 峰值窗口大小 | 日监控中的 RPM 峰值时段 | ±10~11 分钟 |
| 插值目标 RPM | 日监控峰值 × 压力系数（通常 2~7x）| ziwei: 29×~3.5=100；hepan: 63×~2.4=150 |
| 是否需要拼接 | 多段峰值间隔 >5min | 有间隔必须先拼接 |
| 脏数据过滤 | content 为 list 的多模态行 | 必须过滤，否则 benchmark 报错 |

> **别名验证**：转换完成后检查 `_all.csv` 行数是否接近 `wc -l input.jsonl`。如明显偏低（如只有 1/3），说明 `model_list` 漏了别名，需重跑 convert。

**最终压测数据集命名**：

```
{MODEL_NAME}_selected_combined_Ndays_peak_poisson_{RPM}_stitched.csv   ← 峰值回放（推荐）
{MODEL_NAME}_all.csv                                                    ← 全量压力测试
```

---

## Step 4：远端服务连通性验证

平台（k8s）部署由运维或用户手动完成，完成后获取 endpoint URL。

**格式示例**：

```
https://infer.geniuworks.com/infra-opti-<model-shortname>/v1/chat/completions
```

**验证脚本**：

```bash
source .venv/bin/activate
python scripts/probe/test_remote_services.py
```

验证检查点：

- [ ] HTTP 200，非超时
- [ ] 响应 JSON 结构完整（`choices[0].message.content` 非空）
- [ ] 响应延迟合理（首 token <5s 为正常）
- [ ] 与本地服务响应一致性（同一 prompt 输出风格相符）

---

## Step 5：Benchmark 执行

**参考目录**：`scripts/benchmark/`

### 5.1 选择测试策略

| 策略 | 脚本 | 适用场景 |
|------|------|----------|
| QPS 拐点扫描 | `run_<model>_<tp>_qps_benchmark.sh` | 找最大承载 QPS |
| 高 QPS 边界探索 | `run_<model>_<tp>_high_qps_explore.sh` | 已知大致范围后精细扫描 |
| 全量压力测试 | `run_<model>_<tp>_qps_stress.sh` | 验证长时间稳定性 |

### 5.2 关键参数

新建脚本时参考现有脚本改以下参数：

```bash
TARGET_MODEL="/mnt/ai-llm/<model-name>"
TOKENIZER="/mnt/ai-llm/<model-name>"
DATASET_PATH="${PROJECT_DIR}/datas/output/<model-name>_all.csv"   # 或峰值CSV
SERVER_URL="https://infer.geniuworks.com/infra-opti-<model>/v1/chat/completions"
OUTPUT_DIR="${PROJECT_DIR}/logs/<model>_<tp>_qps_${TIMESTAMP}"
COOLDOWN_SECS=90                    # 档位间冷却，避免残余负载影响下档
```

QPS 档位设计原则：

```
边界区（接近拐点）：步进 0.02，每档 60min
中间区（稳定区）：  步进 0.04，每档 45min
低 QPS 区：        步进 0.05，每档 30min
```

### 5.3 执行

```bash
# 后台长跑（推荐）
nohup bash scripts/benchmark/run_<model>_<tp>_qps_benchmark.sh \
    > logs/<model>_<tp>_qps_$(date +%Y%m%d).log 2>&1 &

# 查看进度
tail -f logs/<model>_<tp>_qps_*.log
cat logs/<model>_<tp>_qps_<timestamp>/progress.txt
```

---

## Step 6：结果分析 & 归档

### 6.1 结果合并（多批次时）

```bash
source .venv/bin/activate
python scripts/analysis/merge_<model>_<tp>_qps_<date>.py
```

合并后目录结构：

```
logs/<model>_<tp>_qps_<date>_all/
  qps_0.50/   qps_0.60/   qps_0.70/ ...
```

### 6.2 分析工具

`analysis` 是 `llm-benchmark` 包安装后注册的 CLI 命令，启动一个本地 Dash Web 服务，在浏览器中加载和浏览 benchmark 结果。

```bash
source .venv/bin/activate

# 启动分析服务（默认端口 8050）
analysis --host 0.0.0.0 --port 8050 --exp /path/to/logs/<experiment-dir>

# 示例
analysis --host 0.0.0.0 --exp /mnt/ai-infra/users/wnd/workspace/execute/guofan/logs/ziwei_4tp_qps_20260310_150343
```

浏览器访问 `http://localhost:8050`，在页面中浏览各 QPS 档位的详细结果，截图关键图表放入 `results/`。

> `--exp` 指向实验根目录（含多个 `qps_X.XX/` 子目录），或单个档位子目录。

### 6.3 结果归档

```
results/<task-name>_<date>/
  REPORT.md              ← 量化报告（参考 reporting-template.md）
  llm_benchmark_summary.md
  *.png / *.html         ← 截图与可视化
```

### 6.4 量化报告关键指标

| 指标 | 说明 | 拐点判断标准 |
|------|------|-------------|
| 成功率 | 请求成功数 / 总发送数 | <99% 视为不稳定 |
| TTFT P90 | 首 token 延迟 90 分位 | >2s 视为过载 |
| Throughput | tokens/s | 线性区趋于平稳即为饱和 |
| 超时率 | 超出 timeout 的请求占比 | >1% 需要关注 |

---

## 接入检查清单

```
[ ] Step 0: 收集模型信息（路径 / GPU / TP / 业务数据 / 平台 URL）
[ ] Step 1: 本地容器启动，健康检查通过
[ ] Step 2: 探测完成（如需），行为特征已记录
[ ] Step 3: 压测数据集已生成，峰值 RPM 达标，脏数据已过滤
[ ] Step 4: 远端 endpoint 连通性验证通过
[ ] Step 5: QPS 扫描完成，日志已保存
[ ] Step 6: 结果合并 & 分析，报告已归档到 results/
```

---

## 环境说明

| 项目 | 路径 |
|------|------|
| Python 虚拟环境 | `/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv` 或 `.venv`（项目根软链）|
| 业务数据根目录 | `/mnt/ai-infra/datasets/` |
| 模型权重根目录 | `/mnt/ai-llm/` |
| Benchmark 工具 | `third_party/speculative-decoding-benchmark/modao/src/` |
| 数据分析工具 | `third_party/data_analysis/scripts/` |
