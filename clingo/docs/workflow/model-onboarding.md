# 新模型接入 SOP

> 模型部署迁移评估标准操作流程  
> 基于 xinghan-ziwei-32b-v1 全流程实践提炼  
> 更新：2026-03-16

---

## 总览

```
━━━━━━━━━━━━━━━ 阶段一：本地准备 ━━━━━━━━━━━━━━━
Step 0  信息收集 & 准入确认
    ↓
Step 1  本地容器部署 & 健康检查       → llm-deployment-docker Skill
    ↓
Step 2  服务探测（无业务数据时）← 可选  → llm-service-probing Skill
    ↓
Step 3  数据处理（JSONL → 压测 CSV）← 可选  → traffic-dataset-prep Skill

━━━━━━━━ 🔴 人工断点：等待平台部署，获取 endpoint URL ━━━━━━━━

━━━━━━━━━━━━━━━ 阶段二：远端评估 ━━━━━━━━━━━━━━━
Step 4  远端服务连通性验证（k8s 平台 endpoint）
    ↓
Step 5  Benchmark 执行（回放 + QPS 扫描）  → llm-replay-benchmark / qps-benchmark-sweep Skill
    ↓
Step 6  结果分析 & 报告归档               → benchmark-result-analysis / qps-sweep-comparison Skill
    ↓
Step 7  生成综合评估报告                  → model-eval-report Skill
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

**model-context.md 初始化**（写入 `results/models/<model-name>/model-context.md`，目录不存在则创建）：

```yaml
model_name: <model-name>
model_path: <model_path>
image: <image>
tp_size: <n>
dp_size: <n>
gpu_ids: "<ids>"
gpu_type: <型号，如 L20 / H100>
max_completion_tokens: <n 或 未提供>
```

---

## Step 1：本地容器部署

> **推荐**：直接使用 `llm-deployment-docker` Skill，可自动完成预检→部署→健康检查→smoke test 全流程。以下为手动参考步骤。

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
TP_SIZE=<TP数>   # NVLink → TP；PCIe → DP（见下）
DP_SIZE=<DP数>
```

> **TP vs DP 选择**：运行 `nvidia-smi topo -m`，有 `NV#` 标记 → TP；全部 PIX/SYS（PCIe）→ DP。  
> PCIe L20 机器强烈建议 `TP=1, DP=N`，避免 AllReduce 通信瓶颈（实测 DP=4 吞吐优于 TP=4 约 1.6x）。

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

**目的**：自动判断模型类型（安全拦截 / 分类路由 / 通用对话）和使用场景。

> **推荐**：直接使用 `llm-service-probing` Skill，3条侦察探针自动判型，无需手动写探测脚本。

**手动探测参考**（不用 Skill 时）：

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

**model-context.md 追加**：

```yaml
model_type: <安全拦截模型 / 分类路由模型 / 通用对话模型>
usage_scenario: <使用场景描述>
```

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

**model-context.md 追加**：

```yaml
business_peak_rpm: <n>
dataset_path: <最终数据集路径>
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

**model-context.md 追加**：

```yaml
endpoint_url: <URL>
baseline_latency_s: <首次响应秒数>
```

---

## Step 5：Benchmark 执行

**参考目录**：`scripts/benchmark/`

### 5.1 选择测试策略

> **推荐**：有业务数据时先跑回放、再跑 QPS 扫描，分别调用对应 Skill。

| 策略 | Skill | 适用场景 |
|------|-------|----------|
| 峰值回放测试 | `llm-replay-benchmark` Skill | 有业务数据时，验证真实流量下成功率/延迟 SLA |
| QPS 拐点扫描 | `qps-benchmark-sweep` Skill | 找最大承载 QPS（后台执行，耗时数小时）|
| 无业务数据 | 仅 `qps-benchmark-sweep` | 以全量数据集扫描替代 |

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

**model-context.md 追加**（回放完成后）：

```yaml
replay_success_rate: <n>%
replay_ttft_p90_s: <x>
replay_ttfs_p90_s: <x>
replay_e2e_p90_s: <x>
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

**回放结果分析**（`benchmark-result-analysis` Skill）：

```bash
# 调用 offline_analysis.py，自动生成 HTML + PNG + REPORT.md 骨架
.venv/bin/python scripts/analysis/offline_analysis.py \
  --csv  logs/<exp_dir>/<exp_name>.csv \
  --out  results/<report_dir>/<exp_name>_analysis.html \
  --png-dir   results/<report_dir> \
  --model-name "<model-name>"
```

脚本终端直接打印 REPORT.md 骨架，含 TTFT/TTFS/E2E 的 P50/P90/P95/P99 真实数值（无需读图）。

**QPS 扫描结果分析**（`qps-sweep-comparison` Skill）：多组对比、拐点识别、SLA 合规评估。

> 如需用旧版交互式 Dash 面板手动探索数据（供调试用）：
> ```bash
> source .venv/bin/activate
> analysis --host 0.0.0.0 --port 8050 --exp /path/to/logs/<experiment-dir>
> ```
> 浏览器访问 `http://localhost:8050`，`--exp` 指向含多个 `qps_X.XX/` 子目录的根目录。

### 6.3 结果归档

```
results/<task-name>_<date>/          ← 单次实验报告
  REPORT.md                          ← 量化报告（含 P50/P90/P95/P99 真实数值）
  llm_benchmark_summary.md
  *.png / *.html                     ← 图表与可视化

results/models/<model-name>/         ← 模型维度汇总（跨实验）
  model-context.md                   ← 结构化上下文，Step 0–6 增量写入
  EVAL_REPORT.md                     ← Step 7 生成的综合评估报告
```

**model-context.md 追加**（QPS 扫描分析后）：

```yaml
sla_max_qps: <x>
sla_threshold: "<模型特定 SLA 门限，如 E2E P95 ≤ 400ms>"
inflection_type: <软拐点 / 硬拐点，及触发指标说明>
```

### 6.4 量化报告关键指标

| 指标 | 说明 | 拐点判断标准 |
|------|------|-------------|
| 成功率 | 请求成功数 / 总发送数 | <99% 视为不稳定 |
| TTFT P90 | 首 token 延迟 90 分位 | >2s 视为过载 |
| Throughput | tokens/s | 线性区趋于平稳即为饱和 |
| 超时率 | 超出 timeout 的请求占比 | >1% 需要关注 |

---

## Step 7：生成综合评估报告

> **推荐**：直接使用 `model-eval-report` Skill，自动读取 `model-context.md` 和各 REPORT.md 生成综合交付报告。

**触发条件**：Step 6 完成，`model-context.md` 中核心字段（`sla_max_qps`、`business_peak_rpm`）已填写。

**调用**：`model-eval-report` Skill
- 传入：模型名称（用于定位 `results/models/<model-name>/`）
- Skill 自动完成：读取 `model-context.md` → 扫描实验 `REPORT.md` → 计算资源建议 → 输出 `EVAL_REPORT.md`

**产物**：

```
results/models/<model-name>/EVAL_REPORT.md
  ├── 第一层：业务摘要（上线建议、推荐规模、资源估算）
  └── 第二层：技术明细（延迟分布、QPS 容量、回放验证详情）
```

**资源建议计算逻辑**（Skill 自动执行）：

```
业务峰值 req/s  = business_peak_rpm ÷ 60
最低实例数      = ceil(业务峰值 req/s ÷ sla_max_qps)
推荐实例数      = ceil(业务峰值 req/s ÷ (sla_max_qps × 0.9))   # 90% 负载率，留 10% 余量
GPU 总数        = 推荐实例数 × tp_size
```

---

## 接入检查清单

```
━━━━━━━━━ 阶段一：本地准备 ━━━━━━━━━
[ ] Step 0: 收集模型信息，model-context.md 已初始化
[ ] Step 1: 本地容器启动，健康检查通过
[ ] Step 2: 探测完成（如需），模型类型已记录，model-context.md 已追加
[ ] Step 3: 压测数据集已生成，峰值 RPM 达标，脏数据已过滤，model-context.md 已追加

━━━━━━━━━ 阶段二：远端评估 ━━━━━━━━━
[ ] Step 4: 远端 endpoint 连通性验证通过，model-context.md 已追加 URL
[ ] Step 5: 回放测试 & QPS 扫描完成，日志已保存，model-context.md 已追加 P90
[ ] Step 6: 结果分析完成，REPORT.md 核心数值已填写（无 <见图> 占位），model-context.md 已追加拐点 QPS
[ ] Step 7: EVAL_REPORT.md 已生成，上线建议明确，推荐规模已计算
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
