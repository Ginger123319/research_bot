---
name: model-evaluation-workflow
description: Use when onboarding a new LLM model end-to-end — from local Docker deployment through data processing, remote endpoint validation, QPS benchmark sweep, replay testing, and final report archiving. Orchestrates all project skills in sequence with automatic skip logic for completed steps and a human handoff checkpoint before remote evaluation.
---

# Model Evaluation Workflow

## Overview

新模型接入的**顶层编排 Skill**，负责协调所有子 Skill 的调用顺序、跳过逻辑和进度记录。

**技术细节不在此 Skill 中**——每步的具体操作参考对应子 Skill 或 `clingo/docs/workflow/model-onboarding.md`。

---

## 两阶段 + 人工断点

```
━━━━━━━━━━━━━━━ 阶段一：本地准备（算法人员给部署规格后即可开始）━━━━━━━━━━━━━━━
  Step 0  信息收集
  Step 1  本地 Docker 部署 & 验证        → llm-deployment-docker Skill
  Step 2  服务探测（无业务数据时）        → llm-service-probing Skill  ⬜ 可跳过
  Step 3  数据处理（有业务数据时）        → traffic-dataset-prep Skill  ⬜ 可跳过

━━━━━━━━━━━━━━━━━━━━ 🔴 人工断点：等待平台部署 ━━━━━━━━━━━━━━━━━━━━
  AI 在此暂停，等待用户提供 k8s endpoint URL

━━━━━━━━━━━━━━━━━━━━ 阶段二：远端评估（拿到 URL 后继续）━━━━━━━━━━━━━━━━━━━
  Step 4  远端连通性验证
  Step 5  Benchmark 执行                → qps-benchmark-sweep Skill
                                        → llm-replay-benchmark Skill（有数据时）
  Step 6  结果分析 & 报告归档           → benchmark-result-analysis Skill
                                        → qps-sweep-comparison Skill
  Step 6.5 实验目录 README & 索引更新  → （强制，无独立 Skill，直接执行）
  Step 7  生成评估报告                  → model-eval-report Skill
```

---

## 会话开始：状态恢复

每次新会话开始时，**先执行以下检查**，确定从哪步续：

```bash
# 1. 读取 progress.md 找到上次停止的位置
# 2. 核查关键产物是否存在（以下任一为空则需重做对应步骤）
ls datas/output_<model>/           # Step 3 产物
docker ps | grep <model>           # Step 1 产物
ls logs/<model>_*_qps_*/           # Step 5 产物
ls results/<model>_*/REPORT.md     # Step 6 产物
ls results/models/<model>/EVAL_REPORT.md  # Step 7 产物
```

向用户说明当前进度后继续。

---

## Step 0：信息收集

**前置检查**：无，每次执行必走。

**需要从用户/算法人员收集**：

| 项目 | 来源 | 是否必须 |
|------|------|---------|
| **部署规格**（二选一）| 算法人员提供 | ✅ |
| &nbsp;&nbsp;形态 A：`python3 -m sglang.launch_server ...` 命令 + 镜像名 | — | — |
| &nbsp;&nbsp;形态 B：Dockerfile（含 ENTRYPOINT 启动命令）| — | — |
| GPU 状态 | `nvidia-smi` 主动检查，无需用户提供 | ✅ |
| 业务数据路径 | 用户提供，或明确"目前无数据" | ✅ |
| **业务峰值 RPM（多通道）** | 见下方⚠️校验步骤 | ✅ |
| 业务推理参数 | 算法人员提供（可选）| ⬜ |
| 远端 endpoint URL | **阶段二再要，此步不需要** | ⏳ |

**从部署规格中提取关键参数**：

```
镜像名        → docker run 的 <image>
--model-path  → 模型路径，同时作为 tokenizer 路径
--port        → 服务端口（检查是否冲突，冲突则重新分配）
--tp-size     → Tensor Parallel 数
--dp-size     → Data Parallel 数
--chat-template → 是否有自定义模板（有则加入 docker run 命令）
--mem-fraction-static / --context-length → 保留，原样透传
```

> 形态 A 示例（ziwei）：
> ```
> python3 -m sglang.launch_server --host 0.0.0.0 --tensor-parallel-size 8 \
>   --model-path /mnt/ai-llm/xinghan-ziwei-32b-v1 --port 5290 \
>   --served-model-name xinghan-ziwei-32b-v1
> 镜像：reg.xxwolo.com/ai/lmsysorg-sglang:latest
> ```
>
> 形态 B 示例（tianji）：提供 Dockerfile，从 ENTRYPOINT 解析所有参数。

**⚠️ 业务峰值 RPM 多通道校验（必做，影响最终实例数）**：

Grafana 裸模型监控（`model="<model-name>"`）**只统计直接 API 调用**，MCP 工具链和 Agent 框架的转发流量**不在裸模型指标中**，可能远大于裸模型峰值。

```
校验步骤：
1. Grafana 裸模型监控 → 获取 stream 峰值 RPM
2. 询问业务方：是否有 MCP/Agent 框架也调用此模型？
   若有 → 查 Grafana MCP 监控，获取各 MCP 工具的峰值 RPM
3. business_peak_rpm = stream_rpm + mcp_rpm（所有通道之和）
```

| 场景 | 后果 |
|------|------|
| 仅看裸模型峰值（43 RPM），漏统 MCP（213 RPM） | 实例建议少 5×（4 实例 → 实际需 20 实例）|

若无法确认 MCP 通道，在 `model-context.md` 中标注 `business_peak_rpm_source: "待核实（仅stream口径）"`，不用该值计算最终实例规模。

**GPU 拓扑自动判断**（`nvidia-smi topo -m`）：

- 算法人员给的 `--tp-size` 基于原始部署环境，本机可能不同
- 若本机为 PCIe（无 NVLink），建议覆盖为 `--tp-size 1 --dp-size N`
- **与用户确认后再调整**，不自行修改

**业务推理参数**（若有，记录备用）：
```json
{
  "temperature": 0.95,  "top_p": 0.90,
  "top_k": 50,          "presence_penalty": 0.4,
  "max_tokens": 4096
}
```
Step 5 benchmark 执行时透传，确保测试条件对齐业务真实调用。

**progress.md 写入**：
```markdown
### Step 0 ✅ 信息收集（YYYY-MM-DD）
- 模型路径：/mnt/ai-llm/<model>
- 镜像：<image>
- 部署参数：TP=<n>, DP=<n>, PORT=<port>
- GPU：<ids>，拓扑：PCIe / NVLink
- 业务数据：有（<路径>）/ 无
- 推理参数：<json 或 "未提供">
- 业务峰值：stream=<n> RPM + MCP=<n> RPM = 合计 <N> RPM（来源：Grafana 已确认/待核实）
```

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

## Step 1：本地 Docker 部署

**前置检查（跳过条件）**：
```bash
docker ps | grep "<model-name>"         # 容器已在运行
curl -sf http://localhost:<port>/health  # 服务已健康
# → 两者均满足则跳过，说明"Step 1 已完成，服务运行中"
```

**调用**：`llm-deployment-docker` Skill
- 传入：模型路径、镜像、端口、Step 0 提取的部署参数
- Skill 自动完成：预检 → docker run → 健康检查 → smoke test → probing（→ Step 2）

**产物验证**：`/health` 200 + smoke test 通过

**progress.md 写入**：
```markdown
### Step 1 ✅ 本地部署（YYYY-MM-DD）
- 容器：<name>，端口：<port>，配置：DP=<n>/TP=<n>
- 健康检查：<n>s 就绪，smoke test 通过
```

---

## Step 2：服务探测

**前置检查（跳过条件）**：
- 用户已提供业务数据 → **跳过**（数据本身说明模型用途）
- `progress.md` 中已有 Step 2 完成记录 → 跳过

> `llm-deployment-docker` Skill 在 smoke test 后会自动调用 `llm-service-probing`，Step 2 通常由 Step 1 连带完成，无需单独触发。

**产物验证**：模型类型判断已输出（安全拦截 / 分类路由 / 通用对话）

**progress.md 写入**：
```markdown
### Step 2 ✅ 服务探测（YYYY-MM-DD）
- 模型类型：<type>
- 使用场景：<描述>
- 注意事项：<如有，否则"无">
```

**model-context.md 追加**：
```yaml
model_type: <安全拦截模型 / 分类路由模型 / 通用对话模型>
usage_scenario: <使用场景描述>
```

---

## Step 2.5：创建模型配置文件（新模型必须）

**前置检查（跳过条件）**：`configs/models/<model>/<tp>.env` 已存在 → 跳过

**操作**：

```bash
# 创建目录
mkdir -p configs/models/<model-name>

# 从 model-context.md 提取参数填充 .env
# 参照已有配置创建（以 chart 为模板）
cp configs/models/xinghan-chart-32b-v1-1-agent/8tp.env \
   configs/models/<model-name>/8tp.env
# 必须修改：MODEL_NAME / MODEL_PATH / SERVER_URL / GROUP_NAME /
#          DATA_FORMAT / INPUT_JSONL / QPS_* / DURATION
# 如有特例：在 .env 对应行加 ⚠️ 注释，并写 configs/models/<model-name>/README.md
```

**产物验证**：`configs/models/<model-name>/8tp.env` 存在，所有必填字段非空

---

## Step 3：数据处理

**前置检查（跳过条件）**：
```bash
ls datas/output_<model>/*_all.csv               # 全量数据集已存在
ls datas/output_<model>/*_poisson_*_stitched.csv  # 泊松插值数据已存在
# → 任一存在则跳过，说明"数据集已就绪"
```
- 用户确认无业务数据 → 跳过，Step 5 改用 `_all.csv` 全量扫描

**调用**：`traffic-dataset-prep` Skill（**新模式：通用脚本方式**）

```bash
# 新模式（推荐，2026-03-18 后新接入模型）
python scripts/data/process.py --env configs/models/<model>/<tp>.env

# 旧模式（历史模型专属脚本，不再维护）
python scripts/data/process_<model>_full.py
```

`DATA_FORMAT` 由 `.env` 决定：
- `standard`：JSONL messages 内联（guoxue/ziwei 类型）→ DataConverter pipeline
- `indexed`：JSONL messages 是 URL（chart 类型）→ 先下载再转换

**产物验证**：`datas/output_<model>/README.md` 存在，核心文件行数合理

**progress.md 写入**：
```markdown
### Step 3 ✅ 数据处理（YYYY-MM-DD）
- 最终数据集：<路径>，<行数> 条，峰值 <RPM> RPM
- 处理方式：standard（JSONL 内联）/ indexed（URL 下载）
```

**model-context.md 追加**：
```yaml
business_peak_rpm: <n>
dataset_path: <最终数据集路径>
```

---

## 🔴 人工断点

**阶段一完成后，AI 主动输出以下内容并停止等待**：

```
【阶段一完成 ✅】本地准备就绪：
  ✅ Step 1  本地服务运行中（http://localhost:<port>）
  ✅ Step 2  模型类型：<type>（<使用场景简述>）
  ✅ Step 3  压测数据集：<路径>（<行数> 条，峰值 <RPM> RPM）
            或：无业务数据，Step 5 将使用全量数据集

请在 k8s 平台完成服务部署后，将 endpoint URL 提供给我：
  格式示例：https://infer.geniuworks.com/infra-<xxx>/v1/chat/completions

提供 URL 后进入阶段二（连通性验证 → Benchmark → 分析报告）。
```

---

## Step 4：远端连通性验证

**前置检查（跳过条件）**：
- `progress.md` 中已有 Step 4 通过记录，且 URL 未变更 → 跳过

**操作**（无对应独立 Skill，直接执行）：
```python
# 三项验证全部通过才算完成
GET  <endpoint_base>/health        → HTTP 200
GET  <endpoint_base>/v1/models     → 返回正确模型 ID
POST <endpoint_base>/v1/chat/completions
     {"messages": [{"role":"user","content":"你好"}], "max_tokens":32}
     → 非空响应，延迟 < 5s
```

**产物验证**：三项全部通过，记录基线延迟

**progress.md 写入**：
```markdown
### Step 4 ✅ 远端连通性验证（YYYY-MM-DD）
- endpoint：<URL>
- 基线延迟：<首次响应>s
```

**model-context.md 追加**：
```yaml
endpoint_url: <URL>
baseline_latency_s: <首次响应秒数>
```

---

## Step 5：Benchmark 执行

**前置检查（跳过条件）**：
```bash
ls logs/<model>_*_replay_*/    # 回放结果已存在 → 跳过回放
ls logs/<model>_*_qps_*_all/   # 合并 QPS 结果已存在 → 跳过扫描
```

**QPS 扫描路径选择（二选一）**：

| 路径 | 适用场景 | Skill |
|------|---------|-------|
| **路径 A**：均匀/密度加权扫描 | 已有历史数据或大致知道拐点范围 | `qps-benchmark-sweep` Skill |
| **路径 B**：三阶段自动逼近 | 拐点完全未知的新模型首次接入 | `qps-peak-finder` Skill |

路径 B 优点：总档位更少（通常 10~15 档 vs 20~30 档），耗时减少约 2/3；需要 `production_rps` 作为 Phase 3 起点。

**执行顺序**（有业务数据时）：
1. 先跑 QPS 扫描（路径 A 或 B）—— 确认最大稳定 QPS
2. sweep/peak-finder 完成后，若需验证真实流量形态，再跑 `llm-replay-benchmark` Skill

无业务数据时：仅跑 QPS 扫描（路径 A）。

**路径 A 执行（新模式，推荐）**：通过 `.env` 配置文件驱动通用脚本

```bash
# QPS sweep（并行启动两组部署对照）
nohup bash scripts/benchmark/run_qps_sweep.sh \
    configs/models/<model>/8tp.env \
    > logs/data-pipeline/<model>_8tp_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &

nohup bash scripts/benchmark/run_qps_sweep.sh \
    configs/models/<model>/4tp.env \
    > logs/data-pipeline/<model>_4tp_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# replay（sweep 完成后，.env 中填好 REPLAY_* 参数）
nohup bash scripts/benchmark/run_replay.sh \
    configs/models/<model>/8tp.env \
    > logs/data-pipeline/<model>_8tp_replay_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```

**路径 A 旧模式（历史参考）**：
```bash
nohup bash scripts/benchmark/run_<model>_qps_sweep.sh \
    > logs/data-pipeline/<model>_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```

**路径 B 执行**：参考 `qps-peak-finder` Skill，自动完成 Phase 1（饱和探测）→ Phase 2（自适应逼近）→ Phase 3（验证网格）

> ⚠️ QPS 扫描耗时长（数小时），启动后告知用户预估时间并 `nohup` 后台执行，不阻塞会话。  
> nohup 重定向路径统一写入 `logs/data-pipeline/`。

**progress.md 写入**：
```markdown
### Step 5 🔄 Benchmark 执行中（YYYY-MM-DD 启动）
- 回放测试：✅ 成功率 <n>%，TTFT P90 <x>s，E2E P90 <x>s
- QPS 扫描：🔄 进行中（路径A/B，<档位范围>，预计 <时长>）
→ 扫描完成后更新为：
### Step 5 ✅ Benchmark 完成（YYYY-MM-DD）
- 拐点 QPS：~<x> req/s（TTFS P90 ≤ 1.5s 基准）
- 日志目录：logs/<model>_*_qps_*_all/ 或 logs/<model>-*-phase3_*/
```

**model-context.md 追加**（回放完成后）：
```yaml
replay_success_rate: <n>
replay_ttft_p90_s: <x>
replay_e2e_p90_s: <x>
```

---

## Step 6：结果分析 & 报告归档

**前置检查（跳过条件）**：
```bash
ls results/<model>_*/REPORT.md  # 报告已存在且完整 → 跳过
```

**调用（与 Step 5 路径对应）**：

| Step 5 路径 | 分析 Skill |
|------------|-----------|
| 路径 A（qps-benchmark-sweep）| `benchmark-result-analysis` + `qps-sweep-comparison` |
| 路径 B（qps-peak-finder）| `benchmark-result-analysis` + **`qps-peak-finder-analysis`** |

- `benchmark-result-analysis` Skill → 回放结果离线分析（HTML + PNG + REPORT 骨架，有回放时）
- `qps-sweep-comparison` Skill → 路径 A：QPS 多组对比（拐点图 + SLA 评估）
- `qps-peak-finder-analysis` Skill → 路径 B：Phase 2+3 合并 + Little's Law 估算 + 三锚点 REPORT

**产物验证**：`results/<model>_<date>/REPORT.md` 核心指标已填写

**progress.md 写入**：
```markdown
### Step 6 ✅ 分析归档（YYYY-MM-DD）
- 报告路径：results/<model>_<date>/REPORT.md
- 关键结论：
  拐点 QPS / ideal_rps：<x> req/s
  回放成功率：<n>%
  TTFT P90：<x>s / TTFS P90：<x>s
```

**model-context.md 追加**：
```yaml
sla_max_qps: <x>
sla_threshold: "<模型特定 SLA 门限描述，如 E2E P95 ≤ 400ms>"
inflection_type: <软拐点 / 硬拐点，及触发指标说明>
# 路径 B（peak-finder）时额外追加：
extreme_rps: <x>
server_concurrency_at_extreme: <n>
```

---

## Step 6.5：实验目录 README & results/README.md 更新（强制）

> 每次 Step 5/6 完成后**必须执行**，确保实验可回溯，不依赖记忆或翻查 logs。

**前置检查（跳过条件）**：`logs/<exp>/README.md` 已存在且结论非空 → 跳过

**操作 1**：为每个新完成的实验目录写 `logs/<exp>/README.md`

每个实验目录的 README 包含：
- 模型名称、部署配置（TP/DP/GPU）、服务 URL、数据集路径
- 测试类型（QPS sweep / 回放）与配置参数
- 快速结论（成功率、拐点 QPS、P90 延迟）
- 结果指针 → `results/<report_dir>/REPORT.md`

参考模板见：
- `qps-benchmark-sweep` Skill → "实验目录 README 归档规范"
- `llm-replay-benchmark` Skill → "实验目录 README 归档规范"

**操作 2**：更新 `results/README.md`

在目录总览表新增一行，并在详细说明节追加完整描述段落。

**操作 3**：`results/models/INDEX.yaml` 中的 `linked_experiments`

将临时占位的 `logs/` 路径替换为正式的 `results/` 路径：
```yaml
linked_experiments:
  - results/<experiment_dir>   # ← 从 logs/ 改为 results/
```

**progress.md 写入**：
```markdown
### Step 6.5 ✅ 实验目录归档（YYYY-MM-DD）
- logs/<exp>/README.md 已写入
- results/README.md 已更新
- INDEX.yaml linked_experiments 已更新为 results/ 路径
```

> ⚠️ `logs/archive/` 用于存放**已过期或合并后的重复实验**，不是已完成实验的归档地点。
> 已完成实验目录保留原位（`logs/<exp>/`），README.md 是其可读性保证。

---

## Step 7：生成评估报告

**前置检查（跳过条件）**：
```bash
# 报告已存在且 Step 6 未更新
ls results/models/<model-name>/EVAL_REPORT.md
```

**调用**：`model-eval-report` Skill
- 传入：model-name（用于定位 model-context.md 和实验报告目录）
- Skill 自动完成：读取 model-context.md → 扫描实验 REPORT.md → 计算资源建议 → 写 EVAL_REPORT.md

**产物验证**：`results/models/<model-name>/EVAL_REPORT.md` 存在，摘要层字段完整

**完成后更新 `results/models/INDEX.yaml`**：
```yaml
# 找到对应模型条目，更新以下字段：
eval_status: completed
eval_completed_date: "YYYY-MM-DD"
performance:
  sla_max_qps_rps: <x>
  sla_max_qps_rpm: <x>
  sla_criterion: "<SLA 门限>"
  replay_success_rate: <n>
  replay_ttft_p90_s: <x>
  replay_e2e_p90_s: <x>
recommendation: "<上线建议一句话>"
paths:
  eval_report: results/models/<model-name>/EVAL_REPORT.md
linked_experiments:
  # 替换临时 logs/ 占位路径为 results/ 正式实验目录
  - results/<experiment_dir_1>
  - results/<experiment_dir_2>
```

**progress.md 写入**：
```markdown
### Step 7 ✅ 生成评估报告（YYYY-MM-DD）
- 报告路径：results/models/<model-name>/EVAL_REPORT.md
- 上线建议：✅ 可上线 / ⚠️ 有条件 / ❌ 暂不建议
- 推荐规模：<N> 实例 × <M> 张 GPU
```

---

## 完成标准

全部步骤完成后输出：

```
【评估完成 ✅】<model-name>
  评估报告：results/models/<model-name>/EVAL_REPORT.md
  上线建议：✅ 可上线
  推荐规模：<N> 实例 × <M> 张 <gpu_type>（共 <GPU总数> 卡）
```

并更新：
- `clingo/docs/README.md` 已跑通模型清单
- `results/models/INDEX.yaml` 对应模型条目（eval_status → completed）

---

## 参考文档

- 完整操作手册：`clingo/docs/workflow/model-onboarding.md`
- 子 Skill 列表：`clingo/docs/planning/skills-roadmap.md`

---

## 验证状态

| 模型 | 状态 |
|------|------|
| xinghan-ziwei-32b-v1 | ⬜ 待回溯验证（已完成全流程，Skill 建成前）|
| tianji-querysafety-4b-v2-3 | ⬜ 待下次接入新模型时完整验证 |
