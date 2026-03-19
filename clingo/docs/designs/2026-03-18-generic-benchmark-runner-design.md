# 通用 Benchmark Runner 设计方案

> 日期：2026-03-18  
> 状态：✅ 已批准，实施中  
> 背景会话：[xinghan-chart-32b 资产化讨论](3681dd54-b8d5-4092-a6de-41038656292c)

---

## 问题背景

当前每接入一个新模型，需新建 2~3 个模型专用脚本（`scripts/benchmark/run_<model>_<tp>_qps.sh`、`scripts/data/process_<model>_full.py`）。这些脚本 **80%+ 逻辑完全相同**，仅顶部约 10 个参数不同。随着模型数量增长，带来两类问题：

| 问题 | 表现 |
|------|------|
| **扩张** | 脚本数量线性增长，scripts/ 目录膨胀 |
| **腐化** | 底层工具升级时（如 `example_llm_benchmark_test.sh` 参数变化）需逐一修改所有脚本 |

---

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 旧脚本处理 | 保留为历史参考，不再维护 | 已完成评估的模型有存档价值 |
| 新模型执行模式 | 通用脚本 + `.env` 配置文件（方案 C）| AI Agent 为主执行者，bash source 原生支持，零新依赖 |
| 配置粒度 | 每个部署一个 `.env`（8TP/4TP 各一份）| 一个模型可有多个部署对照，配置独立 |
| 特例处理 | `configs/models/<model>/README.md` 记录 | 不修改通用脚本，累积特例找共性后统一迭代 |
| 配置内容 | 数据处理 + benchmark 参数合并一文件 | 单文件覆盖全流程，AI 一次生成可复用 |

---

## 目录结构

```
configs/
  models/
    <model-name>/
      <tp>.env        ← 该部署的全量配置（数据处理 + benchmark）
      README.md       ← 特例说明、参数来源备注、已知问题
    xinghan-chart-32b-v1-1-agent/
      8tp.env         ← 首个采用新模式的模型
      4tp.env
      README.md

scripts/
  benchmark/
    run_qps_sweep.sh  ← 通用 QPS 拐点扫描（新）
    run_replay.sh     ← 通用峰值回放（新）
    run_*.sh          ← 旧脚本，历史参考，不再维护
  data/
    process.py        ← 通用数据处理入口（新）
    process_*.py      ← 旧脚本，历史参考，不再维护
```

---

## `.env` 文件规范

每个部署配置文件包含以下固定分节，**全部字段必须显式赋值**（不依赖缺省值）：

```bash
# ══════════════════════════════════════════════════════
# <MODEL_NAME>  <TP>TP 部署配置
# 生成时间: YYYY-MM-DD
# ══════════════════════════════════════════════════════

# ── 模型基础 ──────────────────────────────────────────
MODEL_NAME=""           # 模型完整名称（与 results/models/ 目录名一致）
MODEL_PATH=""           # 本地模型权重路径（用于 tokenizer 初始化）
TOKENIZER=""            # tokenizer 路径（通常与 MODEL_PATH 相同）

# ── 数据处理 ──────────────────────────────────────────
DATA_FORMAT=""          # standard（messages 内联 list）| indexed（raw_content URL）
INPUT_JSONL=""          # 原始索引/数据 JSONL 路径（相对 PROJECT_DIR）
OUTPUT_DIR=""           # 处理产物输出目录（相对 PROJECT_DIR）
MODEL_LIST=""           # 模型别名，逗号分隔（必须覆盖 JSONL 中所有写法）
DATASET_PATH=""         # 最终 benchmark 数据集路径（相对 PROJECT_DIR）
DATASET_TYPE=""         # all（全量，QPS sweep 用）| peak（峰值采样，replay 用）
TARGET_PEAK_RPM=""      # 峰值 RPM（peak 类型时用于插值目标，all 类型留空）

# ── Benchmark 公共参数 ─────────────────────────────────
SERVER_URL=""           # 远端 k8s endpoint URL
GROUP_NAME=""           # 日志目录前缀，格式 <model-short>-<tp>tp
MAX_COMPLETION_TOKENS="" # 模型输出最大 token（对话 4096，安全拦截 256）
COOLDOWN_SECS=""        # 档位间冷却秒数（对话模型 90，安全拦截 60）

# ── QPS Sweep 参数 ─────────────────────────────────────
QPS_START=""            # 起始 QPS（通常略高于业务峰值 QPS）
QPS_END=""              # 结束 QPS（通常为业务峰值 QPS 的 2~3x）
NUM_LEVELS=""           # 档位数（首次探索 20，精查 10~15）
DURATION=""             # 每档时长（秒），必须满足：QPS_END × DURATION ≤ 数据集行数

# ── Replay 参数（无回放计划时留空）────────────────────
REPLAY_DATASET_PATH=""  # 峰值回放数据集路径（_poisson_<RPM>_stitched.csv）
REPLAY_RPM=""           # 回放目标 RPM（与文件名对应）
```

### 特殊参数说明规范

遇到非标准值时，在对应行后加注释说明原因：

```bash
DURATION=1500  # ⚠️ 非标 2700s：数据集仅 6016 条，QPS_END×2700=10800 超限
DATA_FORMAT="indexed"  # ⚠️ 非标 standard：chart JSONL 是索引文件，需先下载 raw_content
```

---

## 通用脚本接口

### `scripts/benchmark/run_qps_sweep.sh`

```bash
# 用法
bash scripts/benchmark/run_qps_sweep.sh <config.env>

# 示例
nohup bash scripts/benchmark/run_qps_sweep.sh \
    configs/models/xinghan-chart-32b-v1-1-agent/8tp.env \
    > logs/data-pipeline/chart_8tp_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```

脚本行为：source `<config.env>` → 参数校验 → 生成 QPS 档位序列 → 循环执行 benchmark → 写 progress.txt → 完成汇总

### `scripts/benchmark/run_replay.sh`

```bash
# 用法
bash scripts/benchmark/run_replay.sh <config.env>

# 示例
nohup bash scripts/benchmark/run_replay.sh \
    configs/models/xinghan-chart-32b-v1-1-agent/8tp.env \
    > logs/data-pipeline/chart_8tp_replay_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```

前置检查：`REPLAY_DATASET_PATH` 非空且文件存在，否则退出并提示。

### `scripts/data/process.py`

```bash
# 用法
python scripts/data/process.py --env <config.env>

# 示例
python scripts/data/process.py \
    --env configs/models/xinghan-chart-32b-v1-1-agent/8tp.env
```

根据 `DATA_FORMAT` 分派处理逻辑：
- `standard`：直接调用 DataConverter pipeline（5 步标准流程）
- `indexed`：先调用 `download_by_indices.py`，再执行转换

---

## 特例处理机制

```
遇到特殊情况
    │
    ├─ 参数层面：在 .env 对应行加 ⚠️ 注释
    │
    ├─ 背景层面：写入 configs/models/<model>/README.md
    │   格式：## 特例记录
    │          | 日期 | 参数 | 特殊值 | 原因 |
    │
    └─ 多模型共性发现 → 在 configs/models/README.md（根目录）追加
        格式：## 共性发现
               积累到一定程度 → 提 issue 改进通用脚本
```

### `configs/models/README.md`（根说明文件）

记录所有已发现的特例共性，辅助通用脚本迭代：

```markdown
## 共性发现

| 发现时间 | 模型 | 现象 | 原因 | 影响参数 |
|---------|------|------|------|---------|
| 2026-03-18 | chart | JSONL 是索引文件，非直接数据 | SpecForge 的 raw_content 存储模式 | DATA_FORMAT=indexed |
| 2026-03-18 | chart | 有效数据仅 12.7% | Agent 框架调用不持久化 prompt | DURATION 需按实际行数缩短 |
```

---

## 新模型接入流程（AI Agent 操作步骤）

```
Step 1  读取 results/models/<model>/model-context.md
        提取：模型路径、数据集路径、业务峰值 RPM、endpoint URL、TP 配置

Step 2  创建 configs/models/<model>/ 目录
        生成 <tp>.env（从 model-context.md 自动填充）
        在 .env 中加 ⚠️ 注释标注非标准值

Step 3  python scripts/data/process.py --env configs/models/<model>/<tp>.env
        如有特例 → 记入 configs/models/<model>/README.md

Step 4  nohup bash scripts/benchmark/run_qps_sweep.sh configs/models/<model>/<tp>.env ...
        监控：tail -f logs/data-pipeline/<exp>.log
              cat logs/<group>/qps_<ts>/progress.txt

Step 5  （有回放测试时）
        nohup bash scripts/benchmark/run_replay.sh configs/models/<model>/<tp>.env ...

Step 6  sweep/replay 完成 → 更新 model-context.md → 运行 qps-sweep-comparison Skill
```

---

## Skill 更新说明

以下 4 个 Skill 需在对应位置增加"使用新模式"的说明：

### `qps-benchmark-sweep` Skill

**新增节**：`## 新模式执行方式（推荐）`

- 说明：新模型优先使用 `run_qps_sweep.sh <config.env>` 而非创建新脚本
- 新增：`.env` 文件 `QPS_*` 参数字段对照表
- 新增：执行命令模板（nohup + data-pipeline 日志路径规范）

### `llm-replay-benchmark` Skill

**新增节**：`## 新模式执行方式（推荐）`

- 说明：新模型优先使用 `run_replay.sh <config.env>`
- 新增：`.env` 文件 `REPLAY_*` 参数字段说明
- 新增：前置检查（`REPLAY_DATASET_PATH` 必须非空）

### `traffic-dataset-prep` Skill

**新增节**：`## 新模式执行方式（推荐）`

- 说明：新模型优先使用 `process.py --env <config.env>`
- 新增：`DATA_FORMAT` 枚举说明（standard / indexed）
- 新增：`MODEL_LIST` 别名验证提示（转换后检查 _all.csv 行数）

### `model-evaluation-workflow` Skill

**Step 3 更新**：

```
旧：每模型新建 process_<model>_full.py
新：创建 configs/models/<model>/<tp>.env → python scripts/data/process.py --env <config.env>
```

**Step 5 更新**：

```
旧：每模型新建 run_<model>_<tp>_qps_sweep.sh
新：bash scripts/benchmark/run_qps_sweep.sh configs/models/<model>/<tp>.env
    bash scripts/benchmark/run_replay.sh configs/models/<model>/<tp>.env
```

**新增 Step 2.5**：创建 `configs/models/<model>/` 目录 + `.env` 配置文件

---

## 实施清单

```
[x] 设计文档（本文件）
[ ] scripts/benchmark/run_qps_sweep.sh        ← 通用 QPS sweep
[ ] scripts/benchmark/run_replay.sh           ← 通用 replay
[ ] scripts/data/process.py                   ← 通用数据处理入口
[ ] configs/models/README.md                  ← 共性发现根文档
[ ] configs/models/xinghan-chart-32b-v1-1-agent/8tp.env   ← 首个模型配置
[ ] configs/models/xinghan-chart-32b-v1-1-agent/4tp.env
[ ] configs/models/xinghan-chart-32b-v1-1-agent/README.md
[ ] clingo/docs/skills/qps-benchmark-sweep/SKILL.md        ← 新增节
[ ] clingo/docs/skills/llm-replay-benchmark/SKILL.md       ← 新增节
[ ] clingo/docs/skills/traffic-dataset-prep/SKILL.md       ← 新增节
[ ] clingo/docs/skills/model-evaluation-workflow/SKILL.md  ← Step 更新
```
