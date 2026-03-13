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
ls results/<model>_*/REPORT.md    # Step 6 产物
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

---

## Step 3：数据处理

**前置检查（跳过条件）**：
```bash
ls datas/output_<model>/*_poisson_*_stitched.csv  # 泊松插值数据已存在
ls datas/output_<model>/*_peak*.csv               # 峰值窗口数据已存在
# → 任一存在则跳过，说明"数据集已就绪"
```
- 用户确认无业务数据 → 跳过，Step 5 改用 `_all.csv` 全量扫描

**调用**：`traffic-dataset-prep` Skill
- 情况 A：JSONL 日志 → 6步管道
- 情况 B：CSV + 系统提示模板 → Skill 情况 B 路径

**产物验证**：`datas/output_<model>/README.md` 存在，核心文件行数合理

**progress.md 写入**：
```markdown
### Step 3 ✅ 数据处理（YYYY-MM-DD）
- 最终数据集：<路径>，<行数> 条，峰值 <RPM> RPM
- 处理方式：情况 A（JSONL）/ 情况 B（CSV+模板）
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

---

## Step 5：Benchmark 执行

**前置检查（跳过条件）**：
```bash
ls logs/<model>_*_replay_*/    # 回放结果已存在 → 跳过回放
ls logs/<model>_*_qps_*_all/   # 合并 QPS 结果已存在 → 跳过扫描
```

**执行顺序**（有业务数据时）：
1. 先跑 `llm-replay-benchmark` Skill —— 峰值回放，验证成功率/延迟 SLA
2. 再跑 `qps-benchmark-sweep` Skill —— QPS 拐点扫描（耗时数小时，后台执行）

无业务数据时：仅跑 `qps-benchmark-sweep`。

**推理参数透传**（Step 0 若收集了业务推理参数）：
```bash
# benchmark 命令附加参数示例
--temperature 0.95 --top-p 0.90 --max-completion-tokens 4096
```

> ⚠️ QPS 扫描耗时长（数小时），启动后告知用户预估时间并 `nohup` 后台执行，不阻塞会话。

**progress.md 写入**：
```markdown
### Step 5 🔄 Benchmark 执行中（YYYY-MM-DD 启动）
- 回放测试：✅ 成功率 <n>%，TTFT P90 <x>s，E2E P90 <x>s
- QPS 扫描：🔄 进行中（<档位范围>，预计 <时长>）
→ 扫描完成后更新为：
### Step 5 ✅ Benchmark 完成（YYYY-MM-DD）
- 拐点 QPS：~<x> req/s（TTFS P90 ≤ 1.5s 基准）
- 日志目录：logs/<model>_*_qps_*_all/
```

---

## Step 6：结果分析 & 报告归档

**前置检查（跳过条件）**：
```bash
ls results/<model>_*/REPORT.md  # 报告已存在且完整 → 跳过
```

**调用**：
- `benchmark-result-analysis` Skill → 回放结果离线分析（HTML + PNG + REPORT 骨架）
- `qps-sweep-comparison` Skill → QPS 多组对比（拐点图 + SLA 评估）

**产物验证**：`results/<model>_<date>/REPORT.md` 核心指标已填写

**progress.md 写入**：
```markdown
### Step 6 ✅ 分析归档（YYYY-MM-DD）
- 报告路径：results/<model>_<date>/REPORT.md
- 关键结论：
  拐点 QPS：<x> req/s
  回放成功率：<n>%
  TTFT P90：<x>s / TTFS P90：<x>s
```

---

## 完成标准

全部步骤完成后输出：

```
【评估完成 ✅】<model-name>
  报告：results/<model>_<date>/REPORT.md
  结论：拐点 QPS <x> req/s，峰值回放成功率 <n>%，可上线。
```

并更新 `clingo/docs/README.md` 已跑通模型清单。

---

## 参考文档

- 完整操作手册：`clingo/docs/workflow/model-onboarding.md`
- 子 Skill 列表：`clingo/docs/skills/skills-roadmap.md`

---

## 验证状态

| 模型 | 状态 |
|------|------|
| xinghan-ziwei-32b-v1 | ⬜ 待回溯验证（已完成全流程，Skill 建成前）|
| tianji-querysafety-4b-v2-3 | ⬜ 待下次接入新模型时完整验证 |
