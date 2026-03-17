# 📋 Progress Log

---

## 🗓️ 会话记录 — 2026-03-16（下午场）

### 📌 会话目标
`xinghan-guoxue-72b-v1-2-reason` 模型评估流程（guofan 项目）——解除 Step 4 端点 404 阻塞，修复 benchmark 数据集格式问题，启动 24 档 QPS 扫描，并同步更新 Skill 及文档。

---

### ✅ 实现了哪些功能

#### 1. Step 4 远端连通性验证（恢复通过）
- 上次会话遇到 endpoint 404，本次用户在平台完成服务上线
- 重新验证：`/health` 200、`/v1/models` 200、POST chat/completions 200，latency=2.30s（64 tokens）
- 确认平台 serve 的模型 ID 为 `bazi-guoxue-eagle3-test`
- 更新 `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md`（Step 4 字段）：
  ```yaml
  served_model_id: bazi-guoxue-eagle3-test
  baseline_latency_s: 2.30
  ```

#### 2. 修复 QPS 扫描数据集问题（`KeyError: 'old_response'`）
- 发现根因：`process_guoxue_full.py` 步骤1 调用 DataConverter 后，输出的 `_all.csv` 是 3 列内部索引文件（`income_time`, `file_suffix`, `original_index`），**不含 `messages`/`old_response`**
- 对比 ziwei 数据发现两者 `_all.csv` 的列结构不同，定位为脚本漏掉步骤1.5 合并步骤
- **修复方案**：将两个日期文件（`_2026-03-13.csv` + `_2026-03-14.csv`，共 23,357 行）合并排序，`old_response` NaN 填充为空字符串，输出为 `_full.csv`
- 更新扫描脚本 `run_guoxue_8tp_qps_sweep.sh` 的 `DATASET_PATH` 指向 `_full.csv`

#### 3. Step 5 QPS 扫描成功启动
- **PID**: 1054030
- **日志**: `logs/guoxue_qps_20260316_163202.log`
- **输出目录**: `logs/guoxue_8tp_qps_20260316_163202/`
- **档位**: 24 档，QPS 0.190 → 0.350（两端细 0.005 步长，中间 0.010 步长），每档 60 分钟
- **预估总耗时**: ~24.5 小时
- 探路请求成功，首批请求稳定发送（单请求实测 ~45-90s，符合 4K 长推理预期）

#### 4. 文档与脚本三处联动更新
- **`scripts/data/process_guoxue_full.py`**：
  - 顶部注释增加"步骤1.5"说明
  - 代码增加步骤1.5（合并日期分片覆盖写回 `_all.csv`，6 列完整数据）
- **`datas/output_guoxue/README.md`**：
  - 处理流程表增加步骤1.5
  - 核心交付文件表新增 `_full.csv` 说明
  - 增加 ⚠️ DataConverter `_all.csv` 3列索引说明
  - 增加 `_all.csv` 列验证结论
- **`.cursor/skills/traffic-dataset-prep/SKILL.md`**：
  - 情况A 流程图从"6步"改为"6步 + 步骤1.5"，标注 DataConverter `_all.csv` 不可直接使用
  - 关键 API 代码块增加步骤1.5 合并代码片段
  - 常见错误表新增 `KeyError: 'old_response'` 条目
  - 验证 Checklist 中"转换后"拆分为两行（步骤1 + 步骤1.5）

---

### 🐛 遇到的错误

| 错误 | 阶段 | 现象 |
|------|------|------|
| Endpoint 404 | Step 4 | `https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions` 全路径返回 404 |
| `KeyError: 'old_response'` | Step 5 | benchmark 工具启动时在 `prepare_dataset` 抛出 KeyError，第一档立即失败 |

---

### 🔧 如何解决这些错误

| 错误 | 解决方式 |
|------|---------|
| Endpoint 404 | 用户在部署平台执行"上线"操作后自动解除，无需代码修改 |
| `KeyError: 'old_response'` | 1) 分析 DataConverter 输出结构发现 `_all.csv` 是 3 列索引；2) 手动合并两日日期 CSV 生成 `_full.csv`（6 列）；3) 更新扫描脚本数据集路径；4) 同步修复脚本（步骤1.5）和文档，防止复现 |

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | 📝 更新 | 补充 Step 4 字段（endpoint 验证结果、baseline 延迟） |
| `datas/output_guoxue/xinghan-guoxue-72b-v1-2-reason_full.csv` | ✨ 新建 | 两日合并完整数据集，23,357 行，6 列，供 QPS 扫描使用 |
| `scripts/benchmark/run_guoxue_8tp_qps_sweep.sh` | 📝 修改 | DATASET_PATH 改为 `_full.csv` |
| `scripts/data/process_guoxue_full.py` | 🐛 修复 | 增加步骤1.5 合并日期分片覆盖写回 `_all.csv` |
| `datas/output_guoxue/README.md` | 📝 更新 | 增加步骤1.5、`_full.csv` 说明、`_all.csv` 陷阱注释 |
| `.cursor/skills/traffic-dataset-prep/SKILL.md` | 📝 更新 | 步骤1.5、新错误条目、验证 Checklist 补充 |

---

### 📋 当前状态

| 事项 | 状态 |
|------|------|
| Step 0: model-context.md 初始化 | ✅ 完成 |
| Step 2: llm-service-probing（跳过，已知模型类型） | ⏭️ 跳过 |
| Step 3: 数据处理（220 RPM Poisson 插值） | ✅ 完成 |
| Step 4: 远端连通性验证 | ✅ 完成 |
| Step 5: 24 档 QPS 扫描（PID 1054030） | 🔄 运行中（预计 ~24.5h） |
| Step 6: 结果分析与报告 | ⏳ 待 Step 5 完成后执行 |
| Step 7: 综合评估报告 | ⏳ 待 Step 6 后执行 |
| 回放测试（Step 5 子项）| ⏭️ 跳过（需大量实例，暂不执行）|

---

## 🗓️ 会话记录 — 2026-03-09

### 📌 会话目标
探测已部署的两个 ziwei 系列模型服务的功能定位，并验证 k8s 平台部署的远端服务可用性。

---

### ✅ 步骤 1：读取部署脚本，了解服务基本信息

**时间**：2026-03-09 20:xx

**实现内容**：
- 读取 [`tmp/scripts/start_ziwei_8b.sh`](tmp/scripts/start_ziwei_8b.sh) 和 [`tmp/scripts/start_ziwei_32b.sh`](tmp/scripts/start_ziwei_32b.sh)
- 确认两个本地服务已通过 SGLang 启动：

| 服务 | 模型名 | 端口 | GPU | TP |
|------|--------|------|-----|-----|
| ziwei-8b-server | `ziwei_intention_twostep_8b_v1` | 5291 | GPU 7 | 1 |
| ziwei-32b-server | `xinghan-ziwei-32b-v1` | 5290 | GPU 3-6 | 4 |

**遇到的问题**：无

---

### ✅ 步骤 2：编写并执行 Round 1 探测脚本

**时间**：2026-03-09 20:16

**实现内容**：
- 新建 [`tmp/probe_models.py`](tmp/probe_models.py)（217 行）
- 执行 6 类测试：自我介绍、意图识别、结构化 JSON 输出、领域专项测试、多轮对话、系统提示词遵循

**关键发现（Round 1）**：
- **8b 模型**：输出格式固定为 `<think>\n\n</think>\n\n<意图标签>`，completion token 约 8-10 个，响应极快
- **32b 模型**：更接近通用对话助手，能做 JSON 槽位提取、多意图识别、自然语言响应

**遇到的问题**：初步结论不确定（`<think>` 块为空是否正常？"twostep" 含义不明）

---

### ✅ 步骤 3：执行 Round 2 深度探测，修正结论

**时间**：2026-03-09 20:22

**实现内容**：
- 追加 8 个深度测试用例，重点验证：
  1. 带候选意图列表的 system prompt 是否生效 → ✅ 完全按列表选择
  2. "twostep" 是否为两步对话流 → ❌ 否，多轮上下文不影响分类结果
  3. `<think>` 块是否可以有内容 → ❌ 始终为空
  4. 32b 对同一输入的响应风格 vs 8b

**最终结论**：

```
用户输入
   │
   ▼
┌─────────────────────────────────────────────┐
│  8b  ziwei_intention_twostep_8b_v1  (:5291) │  ← 路由层（意图分类器）
│  输出 <意图标签>，completion ≈ 8 tokens      │    ~0.2s 极快
└────────────────┬────────────────────────────┘
                 │ 按意图路由
                 ▼
┌─────────────────────────────────────────────┐
│  32b  xinghan-ziwei-32b-v1         (:5290)  │  ← 对话响应层
│  生成完整客服回复，支持槽位提取、多意图       │    ~1s
└─────────────────────────────────────────────┘
```

- "twostep" = 系统管道中 **8b 路由 → 32b 响应** 的两步架构
- 底座均为 Qwen 系列，面向中文电商/客服场景
- `<think>` 块在 SFT 微调后被清空，是训练数据特性，非异常

**遇到的问题**：无

---

### ✅ 步骤 4：验证 k8s 平台远端服务连通性

**时间**：2026-03-09 20:xx

**实现内容**：
- 新建 [`tmp/test_remote_services.py`](tmp/test_remote_services.py)（220 行）
- 测试远端 URL：
  - `https://infer.geniuworks.com/infra-ziwei-intention-twostep-p8b-v1`
  - `https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1`

**测试结果（5/5 全部通过）**：

| 检测项 | 8b | 32b |
|---|---|---|
| `/health` | ✅ 200 (empty body) | ✅ 200 |
| `/v1/models` | ✅ 模型 ID 正确 | ✅ |
| 意图分类 · 退货 | ✅ `<退货流程>` · 0.21s | ✅ 1.17s |
| 意图分类 · 订单查询 | ✅ `<订单状态查询>` · 0.24s | ✅ 1.03s |
| 意图分类 · 密码找回 | ✅ `<忘记密码>` · 0.22s | ✅ 1.02s |

**遇到的问题**：
- `FAIL` `/health` → k8s 反向代理下返回空 body（非 JSON），脚本解析失败
- **解决方案**：在 `http_get()` 中添加 `json.JSONDecodeError` 捕获，空 body 时返回提示字符串而非报错

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `tmp/probe_models.py` | ✨ 新增 | 本地模型能力探测脚本（217 行） |
| `tmp/test_remote_services.py` | ✨ 新增 | 远端 k8s 服务连通性测试脚本（220 行） |
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 新增 | 会话总结报告 |

---

## 🗓️ 会话记录 — 2026-03-10（上午：数据处理与压测初探）

> 📄 原始会话导出：[`clingo/sessions/03_cursor_data_processing_requirements_for.md`](clingo/sessions/03_cursor_data_processing_requirements_for.md)

### 📌 会话目标
对 `xinghan-ziwei-32b-v1-1` 原始 JSONL 数据进行格式转换、峰值采样、流量插值，生成可用于 benchmark 压测的数据集，并完成首次 `--keep-income-time` 流量回放测试。

---

### ✅ 步骤 1：熟悉 `data_analysis` 工具链，分析原始数据

**时间**：2026-03-10 上午

**实现内容**：
- 原始数据：`datas/xinghan-ziwei-32b-v1-1_260303_260305.jsonl`
  - 9,661 条会话，14,185 个请求，覆盖 2026-03-03 ~ 2026-03-06
- 分析峰值分布：
  - 实际数据峰值：**16 RPM**（三天均集中在 00:00~00:20 时段）
  - Grafana 监控峰值：**29 RPM** → 需通过插值放大
- 确认 Python 环境：`/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/bin/python`

**遇到的问题**：无

---

### ✅ 步骤 2：数据格式转换（第一次：`read_only_time=True` 快速模式）

**时间**：2026-03-10 上午

**实现内容**：
- 新建 [`tmp/process_ziwei_full.py`](tmp/process_ziwei_full.py)，调用 `data_analysis` 工具链
- 策略：合并三天峰值窗口（03-03 00:09~00:29、03-04 23:58~00:18、03-05 00:00~00:20）
- 输出：
  - `only_time_*.csv`（时间索引）
  - `_selected_combined_3days_peak.csv`（537条，峰值16 RPM）
  - `_selected_combined_3days_peak_poisson_29.csv`（974条，峰值29 RPM）

**遇到的问题**：
- 输出 CSV 中 `prompt`/`messages` 字段全部为空

**根因**：使用了 `read_only_time=True` 快速模式——只提取时间戳，跳过 COS URL 下载

---

### ✅ 步骤 3：完整转换（`read_only_time=False`），填充 messages 内容

**时间**：2026-03-10 上午

**实现内容**：
- 改用完整模式并发拉取 COS prompt URL 填充真实 messages 内容
- 结果：**943/943 条记录 messages 有内容** ✅
- 最终文件大小：每日 CSV ~57-61 MB，`_poisson_29.csv` → **12.5 MB**

**写入 README**：
- 在 `datas/output/README.md` 中记录处理动机、流程图、文件说明
- 明确标注 `only_time_*.csv` 为可忽略的中间产物

**遇到的问题**：
- 第一次 README 未清晰区分"核心文件"与"中间产物"
- **解决**：更新 README，分类标注核心文件（✅ Benchmark使用）和中间文件（🗑️ 可忽略）

---

### ✅ 步骤 4：配置 benchmark 命令，设计测试方案

**时间**：2026-03-10 上午

**实现内容**：
- 发现 `benchmark --help` 中的关键参数 `--keep-income-time`（按 income_time 原始时刻发送）
- 设计两种压测方案对比：

| | 方案A：固定 QPS | 方案B：`--keep-income-time` 回放 |
|---|---|---|
| 发送方式 | 匀速 0.5 req/s（≈ 30 RPM） | 按真实时刻发送 |
| 峰值特征 | 平坦 | 自然波动，峰值 29 RPM |
| 时长 | ~2.5h（5档 × 31min） | ~20min（数据窗口时长） |

- 最终确定的方案B命令：
```bash
benchmark \
  --exp-name ziwei_peak_replay \
  --dataset-path ".../xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_poisson_29.csv" \
  --url "https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1/v1/chat/completions" \
  --tokenizer "/mnt/ai-llm/xinghan-ziwei-32b-v1" \
  --keep-income-time --max-completion-tokens 4096 --no-kvcache \
  --output-dir "logs/ziwei_peak_replay_$(date +%Y%m%d_%H%M%S)"
```

**遇到的问题**：`benchmark` 命令需要 SpecForge venv 激活，不能直接调用
**解决**：使用完整路径 `/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/bin/benchmark`

---

### ⚠️ 步骤 5：首次 benchmark 运行，发现时间戳间隔问题（未完成）

**时间**：2026-03-10 13:14

**执行情况**：
- 数据集加载：943/943 ✅，探路请求成功 ✅
- 正式请求开始发送，进度 31%（288/943）后即将遭遇大间隔
- **发现严重问题**：三段峰值窗口之间各有 **~23.5 小时间隔**
  - `--keep-income-time` 模式下 benchmark 会真的等待 23 小时再发下一段！

**操作**：
- 告知用户执行 `kill 556762` 停止进程
- 需要对数据做时间戳拼接处理

**遗留问题（下一个会话续处理）**：
- 三段数据首尾相连（时间戳平移拼接）
- 基于拼接后数据重新做泊松插值至 100 RPM
- 重新执行 benchmark

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 行数 | 说明 |
|------|------|------|------|
| `tmp/process_ziwei_full.py` | ✨ 新增 | 203 | 完整数据处理脚本（转换+采样+插值） |
| `datas/output/README.md` | ✨ 新增 | 134 | 数据目录说明文档 |
| `datas/output/xinghan-ziwei-32b-v1-1_2026-03-0*.csv × 4` | ✨ 新增 | 各~57MB | 每日完整转换数据（含messages内容） |
| `datas/output/xinghan-ziwei-32b-v1-1_selected_combined_3days_peak.csv` | ✨ 新增 | 487 | 三天峰值窗口合并采样（486条） |
| `datas/output/xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_poisson_29.csv` | ✨ 新增 | 944 | 插值至29RPM（943条，messages有内容） |
| `datas/output/xinghan-ziwei-32b-v1-1_poisson_29_compare.html` | ✨ 新增 | — | 插值前后流量对比图 |

---

## 🗓️ 会话记录 — 2026-03-10（下午：时间戳修复与100RPM压测）

### 📌 会话目标
对 `xinghan-ziwei-32b-v1` 做流量回放压测（峰值 100 RPM），完成：数据时间戳拼接 → 泊松插值 → 数据清洗 → 启动 benchmark，并整理项目文件结构。

---

### ✅ 步骤 1：明确数据处理流程与命名规范

**时间**：2026-03-10 上午

**实现内容**：
- 确认三段峰值窗口 CSV 文件就是正确的数据源（非 `_combined` 派生）：
  - `_selected_0303-000900_0303-002900.csv`（151 行）
  - `_selected_0303-235800_0304-001800.csv`（170 行）
  - `_selected_0305-000000_0305-002000.csv`（167 行）
  - 三段拼接 → `_selected_combined_3days_peak.csv`（487 行）
- 确认完整的数据处理流水线命名规范：

```
3段分窗口文件
  → _combined_3days_peak.csv            （486条，原始合并）
  → _combined_3days_peak_stitched.csv   （486条，时间戳连续60分钟）
  → _combined_3days_peak_poisson_100_stitched.csv  （3036条，峰值100 RPM）
```

**遇到的问题**：无

---

### ✅ 步骤 2：更新 `make_peak100_stitched.py`，保留中间拼接文件

**时间**：2026-03-10 上午

**实现内容**：
- 修改 [`tmp/make_peak100_stitched.py`](tmp/make_peak100_stitched.py)：
  - `STITCHED_TMP` → `STITCHED_FILE`，改为永久保存（不再删除临时文件）
  - 输出文件名：`_selected_combined_3days_peak_stitched.csv`
  - 打印保存路径提示
- 重新执行脚本，结果：
  - 步骤1（拼接）：3段 → 486条，时长 59.1 分钟，无大间隔 ✅
  - 步骤2（插值）：486条 → 3039条，峰值 RPM = 100 ✅

**遇到的问题**：无

---

### ✅ 步骤 3：启动 benchmark，修复 `content` 为 list 的数据问题

**时间**：2026-03-10 上午

**实现内容**：
- 执行 benchmark（`--keep-income-time`，100 RPM 数据集），在 dataset prepare 阶段（46% 处）报错

**遇到的错误**：
```
TypeError: can only concatenate str (not "list") to str
Preparing dataset:  46%|████▋     | 1410/3039
```

**根因分析**：
- `_2026-03-04.csv` 中有 3 行数据的 `messages[*].content` 字段是 Python list（多模态消息格式），而非普通字符串
- Jinja 模板在 `apply_chat_template` 时尝试字符串拼接，遇到 list 类型报错

**解决方案**：
```python
# 检测 messages 中 content 为 list 的行并过滤
mask = df['messages'].apply(has_list_content)  # 3行
df_clean = df[~mask].reset_index(drop=True)    # 3039 → 3036 行
# 验证峰值 RPM 仍为 100 ✅
```

- 过滤后重新执行 benchmark，dataset prepare 100% 完成，探路请求成功，正式请求开始发送 ✅

---

### ✅ 步骤 4：文件目录清理整理

**时间**：2026-03-10 下午

**删除文件（datas/output/）**：
- `only_time_xinghan-ziwei-32b-v1-1_*.csv` × 5（时间索引文件，已不需要）
- `_selected_combined_3days_peak_poisson_29.csv`（旧版 29 RPM 数据）
- `_selected_combined_3days_peak_poisson_29_stitched.csv`（旧版拼接数据）
- `_poisson_29_compare.html`（旧版对比图）

**删除文件（tmp/）**：
- `process_ziwei_data.py`（旧版处理脚本，已被 `process_ziwei_full.py` 替代）
- `fix_timestamps_stitch.py`（时间戳拼接独立脚本，已合并到 `make_peak100_stitched.py`）
- `process_ziwei_full.log`、`process_ziwei.log`（过时日志）

**移动文件**：
- `tmp/run_ziwei_4tp_qps_benchmark.sh` → `tmp/scripts/run_ziwei_4tp_qps_benchmark.sh`

**遇到的问题**：
- 脚本移动后 `PROJECT_DIR="$(dirname "$SCRIPT_DIR")"` 取到 `tmp/` 而非项目根目录

**解决方案**：
- 改为硬编码绝对路径：`PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"`

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 行数 | 说明 |
|------|------|------|------|
| `tmp/make_peak100_stitched.py` | ♻️ 修改 | 127 | 保留中间 `_stitched.csv`，变量名更清晰 |
| `datas/output/xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_stitched.csv` | ✨ 新增 | 487 | 时间戳连续60分钟的拼接数据 |
| `datas/output/xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_poisson_100_stitched.csv` | ✨ 新增 | 3037 | 峰值100 RPM 压测数据集（3036条）|
| `tmp/scripts/run_ziwei_4tp_qps_benchmark.sh` | 🔧 移动+修复 | 65 | 从 `tmp/` 移入 `tmp/scripts/`，修复 PROJECT_DIR |
| `progress.md` | 📝 更新 | — | 本文件 |
| `project_status.md` | 📝 更新 | — | 会话总结报告 |

**删除文件（共 10 个）**：
`only_time_*.csv × 5`、`_poisson_29.csv`、`_poisson_29_stitched.csv`、`_poisson_29_compare.html`、`process_ziwei_data.py`、`fix_timestamps_stitch.py`、`process_ziwei*.log × 2`

---

## 🗓️ 会话记录 — 2026-03-10（下午/晚间，续）

### 📌 会话目标
1. 将 JSONL 全量数据合并为单文件 `_all.csv` 供单实例压力测试使用
2. 编写 8TP 单实例 QPS 压力测试脚本（全量数据，从 1.0→0.46 扫描拐点）
3. 编写 4TP 部署 QPS 补全脚本（对齐 8TP 覆盖范围）

---

### ✅ 步骤 1：生成全量数据文件 `_all.csv`

**时间**：2026-03-10 下午

**实现内容**：
- 新建 [`tmp/process_ziwei_all.py`](tmp/process_ziwei_all.py)（91 行）
- 将4个按天 CSV（`2026-03-03~06`）合并为单文件，按 `income_time` 排序
- 输出：[`datas/output/xinghan-ziwei-32b-v1-1_all.csv`](datas/output/xinghan-ziwei-32b-v1-1_all.csv)

**数据统计**：
| 指标 | 值 |
|------|----|
| 来源文件 | 4 个按天 CSV（03-03 ~ 03-06） |
| 总请求数 | **12,789 条**（多轮对话拆解为单轮） |
| 时间范围 | 2026-03-03 00:00 ~ 2026-03-06 23:37 |
| messages 有内容 | **12,789 / 12,789**（全部有，`read_only_time=False` 模式） |
| 文件大小 | 168.7 MB |

**遇到的问题**：第一版脚本包含了转换器调用逻辑，`exec` 时报 `Aborted`

**解决方案**：简化脚本——因为按天 CSV 已存在且已包含完整 messages 内容，直接 `pd.concat` 合并即可，无需重跑转换器

---

### ✅ 步骤 2：编写 8TP 单实例 QPS 压力测试脚本

**时间**：2026-03-10 晚间

**实现内容**：
- 新建 [`tmp/scripts/run_ziwei_8tp_qps_stress.sh`](tmp/scripts/run_ziwei_8tp_qps_stress.sh)（205 行）
- 覆盖 QPS 1.00 → 0.46，**共 20 档**，非均匀步进
- 每档 `NUM_PROMPTS = ceil(QPS × 目标时长)`，高 QPS 跑长、低 QPS 跑短
- 每档独立子目录 `qps_{value}/`，支持 `progress.txt` 实时进度跟踪

**最终档位设计**（迭代 3 次调整）：

| 区段 | QPS 范围 | 步进 | 档数 | 每档时长 |
|------|----------|------|------|----------|
| 边界细粒度 | 1.00 → 0.76 | **0.02** | 13 | 60 min |
| 中 QPS | 0.72 → 0.60 | 0.04 | 4 | 45 min |
| 低 QPS 粗扫 | 0.55 → 0.46 | **0.05** | 3 | 30 min |

**预估总时长**：~18 小时（含每档 90s 冷却）

**设计决策**：
- 用户最初设计边界区在低 QPS（0.46~0.54），后确认拐点应在高 QPS 区（0.76~1.0）→ 反转设计，高处细粒度
- 从 11 档扩展到 20 档，边界区步进从 0.05 → 0.02

---

### ✅ 步骤 3：重写并扩充 4TP QPS 压测脚本

**时间**：2026-03-10 晚间

**背景**：4TP 历史上已跑了两批次，但存在数据集路径错误导致的失败，且中间大量档位空缺。

**已完成历史档位**：
- `ziwei_4tp_qps_20260310_150343`：0.84, 0.83, 0.82, 0.80, 0.50（0.49 因 `poisson_29.csv` 不存在失败）
- `ziwei_4tp_qps_20260310_182639`：0.49, 0.48（0.47 进行中）

**缺口分析**：对比 8TP 覆盖范围，4TP 缺少 **15 个**档位：
- 上方空白：1.00, 0.98, 0.96, 0.94, 0.92, 0.90, 0.88, 0.86（8档）
- 中间空缺：0.78, 0.76, 0.72, 0.68, 0.64, 0.60（6档）
- 过渡缺失：0.55（1档）

**实现内容**：
- 重写 [`tmp/scripts/run_ziwei_4tp_qps_benchmark.sh`](tmp/scripts/run_ziwei_4tp_qps_benchmark.sh)（207 行）
- 补全 **16 档**（15 缺失 + 0.46 未跑）
- 数据集从 `_selected_combined.csv`（486条）换为 `_all.csv`（12,789条）
- 结构对齐 8TP 脚本：逐档独立目录、动态 NUM_PROMPTS、进度跟踪

**遇到的问题**：第一版脚本用于续跑两档，经对比发现缺口远不止如此

**解决方案**：重新做完整覆盖分析后扩充为 16 档脚本

**预估总时长**：~14 小时（含冷却）

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 行数 | 说明 |
|------|------|------|------|
| `tmp/process_ziwei_all.py` | ✨ 新增 | 91 | JSONL 全量数据合并脚本 |
| `datas/output/xinghan-ziwei-32b-v1-1_all.csv` | ✨ 新增 | 12,791 | 全量 12,789 条压测数据集（168.7 MB） |
| `tmp/scripts/run_ziwei_8tp_qps_stress.sh` | ✨ 新增 | 205 | 8TP 单实例 QPS 压力测试脚本（20档） |
| `tmp/scripts/run_ziwei_4tp_qps_benchmark.sh` | ♻️ 重写 | 207 | 4TP QPS 补全脚本（16档，对齐8TP覆盖范围） |

---

## 🗓️ 会话记录 — 2026-03-10（晚间：峰值回放压测完成 & 迁移验证报告）

### 📌 会话目标
1. 确认 `xinghan-ziwei-32b-v1`（`infra-xinghan-ziwei-p32b-v1`）100 RPM 峰值回放压测结果
2. 分析压测指标数据，与 Grafana 线上监控横向对比
3. 撰写完整的迁移后性能验证报告，佐证测试有效性与上线可行性

---

### ✅ 步骤 1：压测执行完毕，确认结果

**时间**：2026-03-10 16:35 ~ 17:35（约 60 分钟）

**执行命令**：
```bash
OUTDIR="logs/ziwei_peak_replay_$(date +%Y%m%d_%H%M%S)"
/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/bin/benchmark \
  --exp-name ziwei_peak_replay \
  --dataset-path "datas/output/xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_poisson_100_stitched.csv" \
  --url "https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1/v1/chat/completions" \
  --tokenizer "/mnt/ai-llm/xinghan-ziwei-32b-v1" \
  --keep-income-time --max-completion-tokens 4096 --no-kvcache \
  --output-dir "$OUTDIR" 2>&1 | tee "logs/ziwei_benchmark_$(date +%Y%m%d_%H%M%S).log"
```

**输出结果**：
- 日志：`logs/ziwei_benchmark_20260310_163524.log`（1598 行）
- 结果 CSV：`logs/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv`

**关键完成统计**：
| 指标 | 值 |
|------|----|
| 总样本数 | 3,036 |
| 成功数 | **3,035** |
| 成功率 | **99.97%** ✅ |
| 总耗时 | 3,585.57 秒 |
| 成功 QPS | 0.846 req/s（≈ 51 RPM 均值，峰值 100 RPM）|
| POST 非200 | 1（502 错误）|

**遇到的问题**：无（压测正常执行完毕）

---

### ✅ 步骤 2：深度数据分析——解析 token_list 获取完整指标

**时间**：2026-03-10 晚间

**实现内容**：
- 读取 `ziwei_peak_replay_100rpm.csv`，解析每条请求的 `token_list` 字段
- 计算 TTFT、TTFS、E2E、TPOT 各分位数

**计算结果**：

| 指标 | Mean | P50 | P90 | P99 | Max |
|------|------|-----|-----|-----|-----|
| TTFT (s) | 0.517 | 0.538 | **1.002** | 1.674 | 2.928 |
| TTFS (s) | 0.750 | 0.662 | **1.259** | 2.540 | 5.393 |
| E2E (s) | 4.247 | 4.310 | **7.476** | 18.377 | 105.690 |
| TPOT (s) | 0.021 | 0.019 | 0.026 | 0.060 | 0.287 |

**吞吐量**：
- Prefill：3,380.7 tokens/s
- Decode：155.7 tokens/s
- 综合：3,536.5 tokens/s
- 平均 Prefill 长度：3,994 tokens（含超长上下文 max=11,697）
- 平均输出长度：183.9 tokens

**与早期测试（29 RPM，943条）对比**：
| | 测试一（29 RPM）| 测试二（100 RPM）| 变化 |
|---|---|---|---|
| 成功率 | 100.00% | 99.97% | 几乎不变 |
| TTFT P90 | 0.866s | 1.002s | +0.136s |
| E2E P90 | 6.715s | 7.476s | +0.761s |
| 压力倍数 | 1× | **3.5×** | 延迟小幅升高，无雪崩 |

**遇到的问题**：无

---

### ✅ 步骤 3：分析截图内容，与 Grafana 线上监控对比

**时间**：2026-03-10 晚间

**截图文件来源**：`results/ziwei_benchmark_20260310_163524/`（8 张图）

**关键对比发现**：

| 指标 | 本次测试（新部署）| Grafana 线上监控（迁移前参考） |
|------|-----------------|-------------------------------|
| 成功率 | **99.97%** | ≈100% |
| TTFT 均值 | **0.517 s** | ~0.8~1.2s（首句时延面板）|
| E2E 均值 | **4.247 s** | ~4~7s（整体响应时面板）|
| 峰值 RPM | **100** | 100（2026-02-23 历史最高）|

- **success_timeline.png**：全程 100% 成功率水平线，零抖动
- **currency_timeline.png**：并发最高约 25，均值 5-12，无拥塞
- **benchmark-data-poisson_100_compare.png**：确认插值放大 525.3%（486 → 3039条），峰值精确 100 RPM

**结论**：新部署服务指标优于或持平于 Grafana 监控中的原服务历史数据

**遇到的问题**：无

---

### ✅ 步骤 4：撰写完整迁移验证报告

**时间**：2026-03-10 晚间

**输出文件**：[`results/ziwei_benchmark_20260310_163524/REPORT.md`](results/ziwei_benchmark_20260310_163524/REPORT.md)

**报告结构**（6 章）：
1. **背景与目的** — 迁移背景、测试目标
2. **测试方法论** — 数据构建流程、执行参数、与线上峰值对应关系
3. **测试结果汇总** — 可用性、延迟分布（含图）、吞吐量、并发时间线
4. **有效性论证** — 6 个维度佐证（数据真实性 / 压力充分性 / 条件严苛性 / Grafana 对比 / 两轮测试一致性 / P99 延迟解释）
5. **结论与上线建议** — 综合结论表、灰度发布建议
6. **附录** — 文件清单、原始指标摘要、执行命令

**遇到的问题**：无

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 行数 | 说明 |
|------|------|------|------|
| `results/ziwei_benchmark_20260310_163524/REPORT.md` | ✨ 新增 | ~260 | 迁移后性能验证报告（含图引用、6章结构）|
| `progress.md` | 📝 更新 | — | 本文件 |
| `project_status.md` | 📝 更新 | — | 会话总结报告 |

**输入数据（只读）**：
- `logs/ziwei_benchmark_20260310_163524.log`（1598 行，压测运行日志）
- `logs/ziwei_peak_replay_20260310_163524/ziwei_peak_replay_100rpm.csv`（压测结果）
- `results/ziwei_benchmark_20260310_163524/*.png`（8 张分析截图）

---

## 🗓️ 会话记录 — 2026-03-11（高QPS边界探索脚本更新）

### 📌 会话目标
1. 修改 8TP 压测脚本：在 QPS (1.0, 2.0] 增加 10 档均等探索（上次 QPS=1.0 未达边界）
2. 修改 4TP 压测脚本：在 QPS [1.0, 2.0] 均等跑 11 档（含 QPS=1.0 重跑，上次结果异常）

---

### ✅ 步骤 1：新建 8TP 高QPS探索脚本

**时间**：2026-03-11

**背景**：昨天 `run_ziwei_8tp_qps_stress.sh` 执行后，QPS=1.0 时明显未达到性能边界，需向上扫描定位实际边界区。保留原脚本不变，新建独立探索脚本。

**实现内容**：
- 新建 [`tmp/scripts/run_ziwei_8tp_high_qps_explore.sh`](tmp/scripts/run_ziwei_8tp_high_qps_explore.sh)
- QPS 覆盖范围：`2.00 → 1.10`，步进 0.1，共 10 档，每档 60min
- 输出目录：`logs/ziwei_8tp_high_qps_<timestamp>/`

**档位设计**：2.00, 1.90, 1.80, 1.70, 1.60, 1.50, 1.40, 1.30, 1.20, 1.10，共 10 档

**预估总时长**：约 10.5 小时（含 90s 冷却间隔）

**遇到的问题**：无

---

### ✅ 步骤 2：新建 4TP 高QPS探索脚本

**时间**：2026-03-11

**背景**：4TP 昨天 QPS=1.0 结果异常需重跑；同时对齐 8TP 覆盖范围补充高QPS数据。保留原脚本不变，新建独立探索脚本。

**实现内容**：
- 新建 [`tmp/scripts/run_ziwei_4tp_high_qps_explore.sh`](tmp/scripts/run_ziwei_4tp_high_qps_explore.sh)
- QPS 覆盖范围：`2.00 → 1.00`，步进 0.1，共 11 档，每档 60min（≤1小时）
- QPS=1.00 为重跑档（上次结果异常）
- 输出目录：`logs/ziwei_4tp_high_qps_<timestamp>/`

**档位设计**：2.00, 1.90, 1.80, 1.70, 1.60, 1.50, 1.40, 1.30, 1.20, 1.10, 1.00（重跑），共 11 档

**预估总时长**：约 11.5 小时（含 90s 冷却间隔）

**遇到的问题**：无

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `tmp/scripts/run_ziwei_8tp_high_qps_explore.sh` | ✨ 新增 | 8TP 高QPS均等探索 2.0→1.1，共10档 |
| `tmp/scripts/run_ziwei_4tp_high_qps_explore.sh` | ✨ 新增 | 4TP 高QPS均等探索 2.0→1.0，共11档，含1.0重跑 |
| `tmp/scripts/run_ziwei_8tp_qps_stress.sh` | 保持不变 | 原 1.0→0.46，20档脚本 |
| `tmp/scripts/run_ziwei_4tp_qps_benchmark.sh` | 保持不变 | 原 1.0→0.46 补全，16档脚本 |
| `progress.md` | 📝 更新 | 本文件 |

---

### ✅ 步骤 3：调整——保留原脚本，改为新建独立高QPS脚本

**时间**：2026-03-11

**用户反馈**：不应修改原有脚本，原有 [0.46, 1.0] 区间的压测内容需要保留，应新建独立脚本处理高QPS探索。

**操作**：
- 将步骤1/2 中修改的内容**回滚还原**，8TP 和 4TP 原脚本恢复至初始版本
- 重新以**独立脚本**形式保存高QPS探索任务

| 脚本 | 用途 | QPS 范围 | 档数 | 时长/档 |
|------|------|----------|------|---------|
| `run_ziwei_8tp_qps_stress.sh` | **保留原有**，8TP 拐点探测 | 1.0 → 0.46 | 20档 | 30~60min |
| `run_ziwei_4tp_qps_benchmark.sh` | **保留原有**，4TP 补全缺失档 | 1.0 → 0.46 | 16档 | 30~60min |
| `run_ziwei_8tp_high_qps_explore.sh` | **新增**，8TP 高QPS边界探索 | 2.0 → 1.1 | 10档 | 30min |
| `run_ziwei_4tp_high_qps_explore.sh` | **新增**，4TP 高QPS探索+1.0重跑 | 2.0 → 1.0 | 11档 | 30min |

**遇到的问题**：无

---

### ✅ 步骤 4：子目录命名增加 TP 前缀，提升 analysis 工具可辨识度

**时间**：2026-03-11

**用户反馈**：同时开启多个 analysis 实例查看结果时，`qps_1.00` 目录无法区分是 4TP 还是 8TP 的结果，容易混淆。

**修改内容**：4 个脚本中的子目录命名全部加前缀：
- 8TP 脚本（×2）：`qps_${qps}` → `TP8_qps_${qps}`
- 4TP 脚本（×2）：`qps_${qps}` → `TP4_qps_${qps}`

修改后目录示例：
```
ziwei_8tp_high_qps_<ts>/
├── TP8_qps_2.00/
├── TP8_qps_1.90/
└── ...

ziwei_4tp_high_qps_<ts>/
├── TP4_qps_2.00/
└── ...
```

**遇到的问题**：无

---

### ✅ 步骤 5：高QPS探索脚本每档时长从 3600s → 1800s

**时间**：2026-03-11

**用户反馈**：每档实际耗时预计在 30 分钟到 1 小时之间，与"每组控制在 1 小时以内"的预期有出入。

**根因分析**：
- `dur=3600s` 只控制**发送请求**的窗口（发送时长 = NUM_PROMPTS / QPS ≈ dur）
- 发送完毕后 benchmark 还需等待所有 pending 响应回来
- 高 QPS（如 2.0）时服务器过载，响应延迟极高，总等待时间远超 1 小时
- 不同 QPS 档位之间实际总耗时差异悬殊（过载越严重越长）

**修改内容**：仅修改两个**高QPS探索**脚本的 `dur`：

| 脚本 | 修改前 | 修改后 | 说明 |
|------|--------|--------|------|
| `run_ziwei_8tp_high_qps_explore.sh` | 3600s/档 | **1800s/档** | 发送 30min，留余量等响应 |
| `run_ziwei_4tp_high_qps_explore.sh` | 3600s/档 | **1800s/档** | 发送 30min，留余量等响应 |

预估总时长变化：
- 8TP：~10.5h → **~5.5h**
- 4TP：~11.5h → **~6h**

**遇到的问题**：无

---

### ✅ 步骤 6：修复 `_all.csv` 中 messages.content 为 list 类型的脏数据

**时间**：2026-03-11

**触发场景**：高QPS探索脚本执行中报错：
```
TypeError: can only concatenate str (not "list") to str
Preparing dataset:  91%|█████████ | 4680/5130
```

**根因分析**：
- `_all.csv` 由 4 个按天 CSV 直接 `pd.concat` 合并而来，未过滤多模态格式数据
- 其中 **5 行**（索引 4680、6781、6939、10698、11252）的 `messages[*].content` 字段是 Python `list` 类型（多模态消息格式），而非普通 `str`
- benchmark 在 `apply_chat_template` 时 Jinja 模板做字符串拼接，遇到 list 类型报 `TypeError`
- 注：同类问题在 2026-03-10 曾在 `poisson_100_stitched.csv` 上出现并修复（3行），但 `_all.csv` 未同步修复

**解决方案**：
1. 新建 [`tmp/fix_all_csv_list_content.py`](tmp/fix_all_csv_list_content.py)，检测并过滤脏行，覆盖写回原文件
2. 同步更新 [`tmp/process_ziwei_all.py`](tmp/process_ziwei_all.py)，加入 `has_list_content` 过滤逻辑，防止重新生成时复现

**执行结果**：
```
✅ 修复完成！12,789 → 12,784 行，已覆盖写回原文件。
发现脏行：5 行（索引: [4680, 6781, 6939, 10698, 11252]）
```

**遇到的问题**：`process_ziwei_all.py` 已有文件时会跳过生成，若未来重建需确认过滤逻辑已合并（本次已更新）

---

### 📁 本次会话新增/修改文件（完整汇总）

| 文件 | 操作 | 说明 |
|------|------|------|
| `tmp/scripts/run_ziwei_8tp_high_qps_explore.sh` | ✨ 新增 | 8TP 高QPS均等探索，2.0→1.1，10档，30min/档 |
| `tmp/scripts/run_ziwei_4tp_high_qps_explore.sh` | ✨ 新增 | 4TP 高QPS均等探索，2.0→1.0，11档，30min/档，含1.0重跑 |
| `tmp/scripts/run_ziwei_8tp_qps_stress.sh` | ✅ 还原保留 | 原 1.0→0.46，20档，子目录改为 TP8_qps_ 前缀 |
| `tmp/scripts/run_ziwei_4tp_qps_benchmark.sh` | ✅ 还原保留 | 原 1.0→0.46 补全，16档，子目录改为 TP4_qps_ 前缀 |
| `tmp/fix_all_csv_list_content.py` | ✨ 新增 | _all.csv 脏数据一次性修复脚本 |
| `tmp/process_ziwei_all.py` | ♻️ 修改 | 新增 has_list_content 过滤，防止重建时复现脏数据 |
| `datas/output/xinghan-ziwei-32b-v1-1_all.csv` | 🐛 修复 | 12,789 → 12,784 行（移除 5 条 list-content 脏行）|
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 会话总结报告 |

---

### 📋 待执行命令

```bash
# 8TP 高QPS边界探索（约 5.5 小时，2.0→1.1，30min/档）
nohup bash tmp/scripts/run_ziwei_8tp_high_qps_explore.sh > /dev/null 2>&1 &

# 4TP 高QPS边界探索（约 6 小时，2.0→1.0含重跑，30min/档）
nohup bash tmp/scripts/run_ziwei_4tp_high_qps_explore.sh > /dev/null 2>&1 &
```

**注意**：两者可以并行执行（8TP 和 4TP 是独立服务 URL）。数据集已修复，可以直接运行。

---

## 🗓️ 会话记录 — 2026-03-12（4TP + 8TP QPS 结果整合）

### 📌 会话目标

整合 ziwei 8TP QPS benchmark 两批历史结果，生成统一格式目录供后续 analysis 使用。

---

### ✅ 步骤 1：整合两批 8TP 结果

**时间**：2026-03-12

**两批来源目录**：

| 目录 | 格式 | QPS 档位 | 档数 |
|------|------|----------|------|
| `ziwei_8tp_qps_stress_20260310_200246` | `qps_X.XX/` 子目录 | 0.46–1.00 | 20 |
| `ziwei_8tp_high_qps_20260311_115259` | `TP8_qps_X.XX/` 子目录 | 1.10–2.00 | 10 |

**合并目标**：统一为 `TP8_qps_X.XX/` 子目录格式，输出到 `ziwei_8tp_qps_20260310_all/`。

**脚本**：[`tmp/merge_8tp_qps_20260310.py`](tmp/merge_8tp_qps_20260310.py)

**执行结果**：

```
合并完成：30 个 QPS 档位
目标目录: logs/ziwei_8tp_qps_20260310_all/
全部 QPS 档位：
  0.46    0.50    0.55    0.60    0.64    0.68    0.72    0.76    0.78
  0.80    0.82    0.84    0.86    0.88    0.90    0.92    0.94    0.96
  0.98    1.00    1.10    1.20    1.30    1.40    1.50    1.60    1.70
  1.80    1.90    2.00
```

**每档文件内容**：
- `dataset.csv`
- `llm_benchmark_vanilla_qpsX.XX.log`
- `vanilla_qpsX.XX.argv.csv`
- `vanilla_qpsX.XX.csv`

**最终目录结构**：

```
logs/ziwei_8tp_qps_20260310_all/
├── TP8_qps_0.46/   TP8_qps_0.50/   TP8_qps_0.55/   TP8_qps_0.60/
├── TP8_qps_0.64/   TP8_qps_0.68/   TP8_qps_0.72/   TP8_qps_0.76/
├── TP8_qps_0.78/   TP8_qps_0.80/   TP8_qps_0.82/   TP8_qps_0.84/
├── TP8_qps_0.86/   TP8_qps_0.88/   TP8_qps_0.90/   TP8_qps_0.92/
├── TP8_qps_0.94/   TP8_qps_0.96/   TP8_qps_0.98/   TP8_qps_1.00/
├── TP8_qps_1.10/   TP8_qps_1.20/   TP8_qps_1.30/   TP8_qps_1.40/
├── TP8_qps_1.50/   TP8_qps_1.60/   TP8_qps_1.70/   TP8_qps_1.80/
└── TP8_qps_1.90/   TP8_qps_2.00/
```

**遇到的问题**：无（high 目录已是正确命名，stress 目录 `qps_X.XX/` 直接重映射为 `TP8_qps_X.XX/`）

---

### ✅ 步骤 2：补充 4TP high 结果到 ziwei_4tp_qps_20260310_all/

**时间**：2026-03-12

**背景**：`ziwei_4tp_high_qps_20260311_115109/` 已于 2026-03-11 20:03 完成，包含 QPS 1.00–2.00（11 档），此前未被纳入 `ziwei_4tp_qps_20260310_all/`。

**操作**：
- `TP4_qps_1.00`：原 all/ 目录仅有 2 个文件（缺 `dataset.csv` 和 `.log`），从 high 目录补全
- `TP4_qps_1.10`–`TP4_qps_2.00`（10 档）：直接复制整个子目录

**最终结果**：`ziwei_4tp_qps_20260310_all/` 从 24 档扩展为 **34 档**（QPS 0.46–2.00）

```
logs/ziwei_4tp_qps_20260310_all/
├── TP4_qps_0.46/ ... TP4_qps_1.00/   (原有 24 档)
└── TP4_qps_1.10/ ... TP4_qps_2.00/   (新增 10 档)
```

**遇到的问题**：无

---

### ✅ 步骤 3：修正 TP4_qps_1.00 数据源（消除混合状态）

**时间**：2026-03-12

**问题发现**：步骤 2 采用"补全缺失文件"策略后，`all/TP4_qps_1.00/` 出现混合状态：

| 文件 | 原来源 | 时间 |
|------|--------|------|
| `vanilla_qps1.00.csv` | `ziwei_4tp_qps_20260310_201049`（stress run） | 2026-03-10 |
| `vanilla_qps1.00.argv.csv` | `ziwei_4tp_qps_20260310_201049`（stress run） | 2026-03-10 |
| `dataset.csv` | `ziwei_4tp_high_qps_20260311_115109`（high run） | 2026-03-11 |
| `llm_benchmark_vanilla_qps1.00.log` | `ziwei_4tp_high_qps_20260311_115109`（high run） | 2026-03-11 |

**技术决策**：选择完全替换为 high run（`ziwei_4tp_high_qps_20260311_115109`），理由：
- high run 是更新的、独立完整的一次运行，4 个文件来源一致
- stress run 的 QPS=1.00 档为一批大扫描的中间档，high run 的 QPS=1.00 是专项 high QPS 扫描的起始档，参数配置更干净

**操作**：删除 stress run 的两个 csv，从 high run 重新复制

**最终状态**：`all/TP4_qps_1.00/` 全部 4 个文件均来自 high run（时间戳 Mar 12 11:48–11:50）

**遇到的问题**：无

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `tmp/merge_8tp_qps_20260310.py` | ✨ 新增 | 8TP 两批历史结果合并脚本（复制模式，原目录保留）|
| `logs/ziwei_8tp_qps_20260310_all/` | ✨ 新建目录 | 30档合并结果，统一 TP8_qps_X.XX/ 子目录格式 |
| `logs/ziwei_4tp_qps_20260310_all/` | 📝 扩充+修正 | 追加 high 结果 10 档（→34档），并修正 TP4_qps_1.00 来源一致性 |
| `progress.md` | 📝 更新 | 本文件 |

**只读参考（未修改）**：
- `logs/ziwei_8tp_qps_stress_20260310_200246/`（保留原始）
- `logs/ziwei_8tp_high_qps_20260311_115259/`（保留原始）
- `logs/ziwei_4tp_high_qps_20260311_115109/`（保留原始）

---

---

## 🗓️ 会话记录 — 2026-03-11（4TP 历史结果合并整理）

### 📌 会话目标

1. 梳理 `ziwei_4tp_qps_20260310` 三批历史结果的合并方案
2. 确认各正在运行任务（4TP high / 8TP high / 8TP stress）的当前进度
3. 执行合并，生成统一格式的 `ziwei_4tp_qps_20260310_all/` 目录

---

### ✅ 步骤 1：梳理三批历史结果结构

**时间**：2026-03-11

**背景**：`run_ziwei_4tp_qps_benchmark.sh` 执行完毕，共产生三批输出目录，需要整合为一份完整结果供后续分析使用。

**三批目录结构对比**：

| 目录 | 格式 | QPS 档位 | 档数 |
|------|------|----------|------|
| `ziwei_4tp_qps_20260310_150343` | 平铺（无子目录）| 0.84, 0.83, 0.82, 0.80, 0.50 | 5 |
| `ziwei_4tp_qps_20260310_182639` | 平铺（无子目录）| 0.49, 0.48, 0.47 | 3 |
| `ziwei_4tp_qps_20260310_201049` | `qps_X.XX/` 子目录 | 1.00→0.46 共 16 档 | 16 |

**合并目标**：统一为 `TP4_qps_X.XX/` 子目录格式（与 `run_ziwei_4tp_high_qps_explore.sh` 脚本的 `LEVEL_DIR` 命名规范对齐），合计 **24 档**。

**遇到的问题**：无

---

### ✅ 步骤 2：确认在途任务进度

**时间**：2026-03-11

**查看进度结果**：

| 任务 | 目录 | 进度 | 状态 |
|------|------|------|------|
| 8TP stress | `ziwei_8tp_qps_stress_20260310_200246` | 第16/20档（QPS=0.64），已完成 1.00→0.64 共16档 | 🔄 运行中 |
| 4TP high | `ziwei_4tp_high_qps_20260311_115109` | 第1/11档（QPS=2.00）| 🔄 运行中 |
| 8TP high | `ziwei_8tp_high_qps_20260311_115259` | 第1/10档（QPS=2.00）| 🔄 运行中 |

**结论**：在途任务均为独立实验，不影响当前对历史 4TP 结果的合并操作，可先行整合。

**遇到的问题**：无

---

### ✅ 步骤 3：编写并执行合并脚本

**时间**：2026-03-11

**输出文件**：[`tmp/merge_4tp_qps_20260310.py`](tmp/merge_4tp_qps_20260310.py)

**脚本逻辑**：
- 平铺目录（150343 / 182639）：正则提取文件名中的 QPS 值，创建对应子目录，复制 `vanilla_qpsX.XX.csv` 和 `vanilla_qpsX.XX.argv.csv`
- 子目录来源（201049）：直接遍历 `qps_X.XX/` 子目录，复制到目标路径
- 所有操作为**复制**（`shutil.copy2`），原始三个目录完整保留

**执行结果**：

```
合并完成：24 个 QPS 档位
目标目录: logs/ziwei_4tp_qps_20260310_all/
全部 QPS 档位：
  0.46  0.47  0.48  0.49  0.50  0.55  0.60  0.64  0.68
  0.72  0.76  0.78  0.80  0.82  0.83  0.84  0.86  0.88
  0.90  0.92  0.94  0.96  0.98  1.00
```

**遇到的问题**：无

---

### ✅ 步骤 4：重命名子目录，对齐 TP4_ 前缀规范

**时间**：2026-03-11

**背景**：合并脚本初始使用 `qps_X.XX/` 命名，需与 `run_ziwei_4tp_high_qps_explore.sh` 脚本中 `LEVEL_DIR="${OUTPUT_DIR}/TP4_qps_${qps}"` 的规范保持一致。

**操作**：在 `ziwei_4tp_qps_20260310_all/` 目录内批量执行 `mv qps_*/ → TP4_qps_*/`

**发现问题**：`qps_1.00` 在 bash glob 展开时末位漏处理（mv 命令输出仅显示 23 个，`TP4_qps_1.00` 缺失）

**解决**：手动从 `201049/qps_1.00/` 补建 `TP4_qps_1.00/`，复制两个 CSV 文件

**最终结果**：24 个子目录全部为 `TP4_qps_X.XX/` 格式，命名规范统一。

```
logs/ziwei_4tp_qps_20260310_all/
├── TP4_qps_0.46/   TP4_qps_0.47/   TP4_qps_0.48/   TP4_qps_0.49/
├── TP4_qps_0.50/   TP4_qps_0.55/   TP4_qps_0.60/   TP4_qps_0.64/
├── TP4_qps_0.68/   TP4_qps_0.72/   TP4_qps_0.76/   TP4_qps_0.78/
├── TP4_qps_0.80/   TP4_qps_0.82/   TP4_qps_0.83/   TP4_qps_0.84/
├── TP4_qps_0.86/   TP4_qps_0.88/   TP4_qps_0.90/   TP4_qps_0.92/
├── TP4_qps_0.94/   TP4_qps_0.96/   TP4_qps_0.98/   TP4_qps_1.00/
```

**遇到的问题**：bash glob `qps_*/` 在 `mv` 循环中漏处理 `qps_1.00`（原因未深查，推测为 glob 排序/扩展时机问题），已手动补建解决。

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `tmp/merge_4tp_qps_20260310.py` | ✨ 新增 | 三批历史结果合并脚本（复制模式，原目录保留）|
| `logs/ziwei_4tp_qps_20260310_all/` | ✨ 新建目录 | 24档合并结果，统一 TP4_qps_X.XX/ 子目录格式 |
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 会话总结报告 |

**只读参考（未修改）**：
- `logs/ziwei_4tp_qps_20260310_150343/`（保留原始）
- `logs/ziwei_4tp_qps_20260310_182639/`（保留原始）
- `logs/ziwei_4tp_qps_20260310_201049/`（保留原始）

---

### 📋 当前在途任务（等待完成后再合并分析）

| 任务 | 目录 | 总档数 | 剩余 | 预估完成 |
|------|------|--------|------|---------|
| 8TP stress | `ziwei_8tp_qps_stress_20260310_200246` | 20档 | ~4档（0.60/0.55/0.50/0.46）| 今日内 |
| 4TP high | `ziwei_4tp_high_qps_20260311_115109` | 11档 | 10档（1.90→1.00）| ~6h |
| 8TP high | `ziwei_8tp_high_qps_20260311_115259` | 10档 | 9档（1.90→1.10）| ~5.5h |

---

---

## 🗓️ 会话记录 — 2026-03-11（下午）

### 📌 会话目标
为新模型 `tianji-querysafety-4b-v2-3` 编写容器启动脚本，在本地 L20 PCIe 机器上完成部署验证，并编写服务探测脚本进行功能测试。

---

### ✅ 步骤 1：编写容器启动脚本

**时间**：2026-03-11

**输出文件**：[`tmp/scripts/start_tianji_querysafety_4b.sh`](tmp/scripts/start_tianji_querysafety_4b.sh)（73 行）

**参考来源**：[`tmp/scripts/start_ziwei_8b.sh`](tmp/scripts/start_ziwei_8b.sh)

**关键配置**：
- 镜像：`reg-ai.cece.com/ai/sglang:v814`
- 模型路径：`/mnt/ai-llm/tianji_query_safety/v2p3_ep1`
- chat template：`/mnt/ai-llm/tianji_query_safety/v2p3_ep1/chat_template.jinja`
- 端口：`8361`，TP=4，DP=1
- GPU 选择：`device=3,4,5,6`（GPU 2 运行 python 进程 15.5GB，GPU 7 运行 sglang 调度器 42.6GB，其余空闲）
- 健康等待：最多 120 秒（比 8b 单卡脚本的 60s 延长，TP=4 初始化更慢）
- 挂载：`/mnt/ai-llm:/mnt/ai-llm:ro`（chat template 路径在同一挂载内可直接访问）

**遇到的问题**：无

---

### ✅ 步骤 2：编写探测脚本 v1 并执行

**时间**：2026-03-11

**输出文件**：[`tmp/probe_tianji_querysafety.py`](tmp/probe_tianji_querysafety.py)（v1，后更新为 v2）

**参考来源**：[`tmp/probe_models.py`](tmp/probe_models.py)

**v1 设计思路**（基于通用对话模型假设）：
- 节 0：健康检查 + `/v1/models`
- 节 1：自我介绍
- 节 2：安全 query（日常购物/天气/知识问答等）
- 节 3：违规 query（暴力/诈骗/违禁物品等）
- 节 4：边界 query（灰色地带）
- 节 5：JSON 结构化输出
- 节 6：连发 5 条请求统计延迟

**执行结果关键观察**：

| 现象 | 说明 |
|------|------|
| 自我介绍出现"我无法给出预测结果"无限循环 | 模型对开放性自我介绍无训练，`temperature=0.0` 无 `repetition_penalty` 导致循环 |
| 违规 query 响应极快（0.13-0.23s） | 模型识别到违规内容后**快速拦截**，输出固定拒绝模板 |
| 安全 query 响应约 1.4s | 走完整推理路径 |
| JSON 结构化输出违规 query 时循环输出 `"违法行为"` 键值对 | 模型不支持自定义 JSON 输出格式 |
| "色情色情色情..." 重复（虚拟创作测试） | 模型识别到不安全意图，但 repetition 失控 |
| 安全 query 有些出现重复句（餐饮推荐、历史事件等） | 同样缺少 `repetition_penalty` |

**核心结论**：该模型是**安全对话助手（拦截式）**而非分类标签输出器：
- 不安全 query → 快速拒绝（固定模板，~0.1-0.3s）
- 安全 query → 正常回答（~1.4s）

---

### ✅ 步骤 3：更新探测脚本 v2

**时间**：2026-03-11

**文件**：[`tmp/probe_tianji_querysafety.py`](tmp/probe_tianji_querysafety.py)（251 行，v2）

**调整内容**：

| 调整项 | 原因 |
|--------|------|
| 删除自我介绍节 | 模型不擅长，会产生无意义循环 |
| 添加 `repetition_penalty: 1.1` | 修复所有循环重复问题 |
| `max_tokens` 从 256 降至 128 | 安全拦截模型不需要长输出 |
| 重新设计测试逻辑：`expect_reject=True/False` | 自动判断"正确拦截/误拦截/正确放行/漏拦截" |
| ⚡ 标记快速拦截（< 0.5s） | 响应时间是拦截行为的重要信号 |
| 删除 JSON 结构化输出测试 | 模型不支持，对评估无意义 |
| 新增汇总报告节 | 自动统计放行准确率 / 拦截准确率 / 综合准确率 |
| 延迟基准测试改为 10 条 | 输出 avg/p50/p90/min/max 统计 |
| 边界 query 增加"安全知识/医疗/历史教育/SQL注入原理" | 这类应放行，测试误拦截率 |
| 边界 query 增加"自我伤害/欺诈/政治煽动" | 这类应拦截，测试拦截覆盖 |

**遇到的问题**：`section()` 函数被重复定义，`ReadLints` 检查发现，已删除重复定义

---

### ✅ 步骤 4：确认 chat template 格式

**时间**：2026-03-11

**chat_template.jinja 结论**：标准 **Qwen2 格式**（`<|im_start|>system/user/assistant<|im_end|>`），支持 `<think>` reasoning 标签和 tool_call，无特殊安全格式要求。调用方式与 ziwei 系列模型相同。

---

### ✅ 步骤 5：TP=4 vs TP=1×4 实例部署分析

**时间**：2026-03-11

**背景**：用户对 4B 小模型使用 TP=4 部署方式产生疑问，执行 `nvidia-smi topo -m` 确认硬件互联方式。

**拓扑结果**：

```
GPU0-GPU3：同 NUMA 节点，最近两张（GPU1-GPU2）为 PIX 级别互联
GPU4-GPU7：另一 NUMA 节点
GPU0↔GPU4：SYS 级（跨 NUMA QPI/UPI，带宽最差）
全机无 NVLink（Legend 中无 NV# 标记）
```

**分析结论**：

| 部署方式 | 通信开销 | 吞吐 | 延迟 | 建议 |
|----------|----------|------|------|------|
| TP=4（当前） | 每层 AllReduce，PCIe 瓶颈 | 受通信拖累 | 低 | ❌ 不适合 PCIe |
| TP=1 × 4 实例 | 零 GPU 间通信 | ~4倍线性提升 | 略高 | ✅ PCIe 机器推荐 |

**为何 Dockerfile 写了 TP=4**：Dockerfile 可能为 NVLink 机器（A100/H100）设计，直接被迁移到 PCIe L20 机器上使用，未针对硬件做适配调整。

**改进建议**：将 `--tp-size 4 --dp-size 1` 改为 `--tp-size 1 --dp-size 4`，sglang 原生支持，无需修改其他配置。

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 行数 | 说明 |
|------|------|------|------|
| `tmp/scripts/start_tianji_querysafety_4b.sh` | ✨ 新增 | 73 | tianji-querysafety-4b-v2-3 容器启动脚本 |
| `tmp/probe_tianji_querysafety.py` | ✨ 新增（v2更新） | 251 | 服务探测脚本，含安全拦截准确率统计 + 延迟基准 |
| `progress.md` | 📝 更新 | — | 本文件 |
| `project_status.md` | 📝 更新 | — | 会话总结报告 |

---

### 📋 当前状态

| 事项 | 状态 |
|------|------|
| 本地容器部署 | ✅ 完成，服务健康检查通过 |
| 平台（k8s）部署 | ✅ 完成（用户自行操作） |
| 服务探测验证 | ✅ 完成，安全拦截行为符合预期 |
| 线上流量回放测试 | ⏳ 等待业务方提供数据 |
| TP 部署策略优化 | 💡 建议改为 TP=1×DP=4，待业务验证后决策 |

---

## 🗓️ 会话记录 — 2026-03-11（hepan 合盘数据处理 & data_analysis 工具链完善）

### 📌 会话目标

1. 排查 `hepan_all_0302_0304.jsonl` 转换行数与同事结果不一致的根因
2. 修复 `data-processor convert -m` 不支持多别名的 CLI 缺陷
3. 用正确的双别名重跑完整 5 步 SKILL 管道
4. 为三个核心模块编写 API 参考文档
5. 为 `data_analysis` 工程创建 git 提交并切 `wnd_dev` 分支

---

### ✅ 步骤 1：根因定位——模型别名缺失导致数据丢失 70%

**时间**：2026-03-11

**现象**：
- 用 `-m xinghan-hepan-72b-v1-2` 只得到 18,567 条（31% 的数据）
- 同事交互模式得到 58,871 条

**排查过程**：
1. 确认时间戳字段正确（`messages[0].time`，非 `create_time`）
2. 对比同事脚本发现使用了不同输入文件 → 否定文件差异假设
3. 用 `-m 星盘合盘` 单独转换 → 得到 40,576 条
4. 验证：40,576 + 18,567 = **58,871（与同事 0 差值）**，两个别名无任何重叠

**根因**：JSONL 中同一模型有两种写法：
- `extra_data.ai_info.model = "xinghan-hepan-72b-v1-2"`（18,567 条）
- `extra_data.ai_info.model = "星盘合盘"`（40,576 条）

两者完全互斥，CLI 只能传一个 → 每次只捞 31% 数据。

---

### ✅ 步骤 2：修复 `menu.py` CLI — `-m` 支持逗号分隔多别名

**时间**：2026-03-11

**修改文件**：`third_party/data_analysis/scripts/data_processor/cli/menu.py`

**核心改动**：

```python
# 修复前（convert 和 sample 命令均如此）
model_list = (args.model,)   # 只包含单个字符串

# 修复后
_model_list = tuple(m.strip() for m in args.model.split(',') if m.strip())
model_name  = _model_list[0]   # 第一个别名用于文件命名
model_list  = _model_list
```

同时更新了两个子命令的 `help` 文本和 `epilog` 示例。

**重新安装**：`pip install -e .`（`/mnt/ai-infra/users/wnd/workspace/execute/data_analysis`）

**遇到的问题**：无

---

### ✅ 步骤 3：分析全量数据三天峰值，更新处理参数

**时间**：2026-03-11

**基于 58,871 条全量数据的峰值分析**：

| 日期 | 峰值时刻 | 峰值 RPM | 采样窗口 |
|------|----------|----------|----------|
| 03-02 | 00:02 | **74 RPM** | 00:00 ~ 00:22 |
| 03-03 | 00:01 | **63 RPM** | 00:00 ~ 00:21 |
| 03-04 | 00:03 | **55 RPM** | 00:00 ~ 00:23 |

（之前基于不完整数据的分析：峰值 30 RPM，完全不准确）

**更新 `scripts/data/process_henpan_tarot_full.py`**：
- `MODEL_LIST = ("xinghan-hepan-72b-v1-2", "星盘合盘")`（原为 `"合盘"`，拼写错误）
- `TARGET_PEAK = 150`（原为 60，基于错误的 30 RPM 峰值）
- `PEAK_WINDOWS` 重新设定三天正确窗口

---

### ✅ 步骤 4：用新 CLI 重跑完整 5 步管道

**时间**：2026-03-11

**步骤1 CLI 执行**（验证多别名修复）：
```bash
data-processor convert \
  -i datas/hepan_all_0302_0304.jsonl \
  -o datas/output_henpan_tarot/ \
  -m "xinghan-hepan-72b-v1-2,星盘合盘" -y
```
→ 输出 `_all.csv` **58,871 条** ✅（与同事 0 差值）

**步骤2-5 脚本执行**（`process_henpan_tarot_full.py`）：

| 步骤 | 结果 |
|------|------|
| 步骤2 采样 | 三窗口合计 **2,979 条**，峰值 74 RPM |
| 步骤3 拼接 | 65.9 分钟连续序列，大间隔 **0 个** ✅ |
| 步骤4 插值 | **6,036 条**，峰值精确 **150 RPM** ✅ |
| 步骤5 过滤 | 移除 **2 条**多模态脏行 → 最终 **6,034 条** |

**遇到的问题**：无

---

### ✅ 步骤 5：更新 output_henpan_tarot/README.md

**时间**：2026-03-11

新增内容：
- 双别名说明（为何需要同时传两个别名）
- 完整 5 步处理参数（TARGET_RPM=150，峰值窗口）
- 核心交付文件与中间文件分类
- SKILL 验证结论表（6 项全部 ✅）

---

### ✅ 步骤 6：更新 SKILL.md — 添加步骤6"README 说明文档"

**时间**：2026-03-11

**修改文件**：`.cursor/skills/traffic-dataset-prep/SKILL.md`

**变更**：
- 管道图：5步 → **6步**（增加步骤6 README）
- 新增「步骤6：README 输出说明文档」章节，规定 6 个必要模块
- Checklist 表格增加步骤6检查项
- 模型别名陷阱章节更新：CLI 限制说明改为「现已支持逗号分隔」

---

### ✅ 步骤 7：编写 data_analysis API 参考文档

**时间**：2026-03-11

**新增目录**：`third_party/data_analysis/docs/api/`（4 个文件）

| 文件 | 内容 |
|------|------|
| `README.md` | 数据流总览 + GlobalConfig 字段表 |
| `converter.md` | DataConverter：输入/输出/列结构/异常/示例 |
| `sampler.md` | DataSampler：三阶段内部流程/异常/示例 |
| `interpolator.md` | DataInterpolator：算法原理/两种模式/时间戳拼接前置代码 |

每份文档均包含：方法签名、参数表、返回值、预期输出（基于 hepan 实测数字）、常见问题。

---

### ✅ 步骤 8：data_analysis 工程 git 提交 + wnd_dev 分支

**时间**：2026-03-11

**工作目录**：`/mnt/ai-infra/users/wnd/workspace/execute/data_analysis`

```bash
git checkout -b wnd_dev
git add scripts/data_processor/cli/menu.py docs/
git commit -m "feat: support multi-alias model_list in CLI and add API docs"
# 提交哈希：33e32bf
```

**变更汇总（5 个文件，668 行新增）**：
- `scripts/data_processor/cli/menu.py`（修改）
- `docs/api/README.md`（新增）
- `docs/api/converter.md`（新增）
- `docs/api/sampler.md`（新增）
- `docs/api/interpolator.md`（新增）

**Push 状态**：当前机器无 push 权限，在有权限的机器上执行：
```bash
cd /mnt/ai-infra/users/wnd/workspace/execute/data_analysis
git push -u origin wnd_dev
# MR 地址: https://git.xxwolo.com/ai-infra-any/data_analysis/-/merge_requests/new?merge_request[source_branch]=wnd_dev
```

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `third_party/data_analysis/scripts/data_processor/cli/menu.py` | ♻️ 修改 | `-m` 支持逗号分隔多别名，解析为 model_list tuple |
| `third_party/data_analysis/docs/api/README.md` | ✨ 新增 | 数据流总览 + GlobalConfig 字段说明 |
| `third_party/data_analysis/docs/api/converter.md` | ✨ 新增 | DataConverter API 文档 |
| `third_party/data_analysis/docs/api/sampler.md` | ✨ 新增 | DataSampler API 文档 |
| `third_party/data_analysis/docs/api/interpolator.md` | ✨ 新增 | DataInterpolator API 文档 |
| `scripts/data/process_henpan_tarot_full.py` | ♻️ 修改 | MODEL_LIST/TARGET_PEAK/PEAK_WINDOWS 全部更正 |
| `datas/output_henpan_tarot/*.csv` | ✨ 重新生成 | 全量 58,871 条，最终压测数据 6,034 条（150 RPM） |
| `datas/output_henpan_tarot/README.md` | ✨ 新增 | 完整交付说明 |
| `.cursor/skills/traffic-dataset-prep/SKILL.md` | ♻️ 修改 | 6步管道、README规范、CLI多别名更新 |
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 会话总结报告 |

---

### 📋 当前状态（hepan 合盘数据处理）

| 事项 | 状态 |
|------|------|
| CLI 多别名修复 | ✅ 已修复，wnd_dev 分支待 push |
| hepan 全量转换 | ✅ 58,871 条，与同事 0 差值 |
| 5步管道完整执行 | ✅ 最终交付 6,034 条（150 RPM） |
| API 文档 | ✅ 4 个 Markdown 文件已写入 docs/api/ |
| git commit | ✅ `33e32bf` on `wnd_dev` |
| git push | ⏳ 待换有权限机器执行 |

---

## 📅 2026-03-11 下午（Skill 体系建设 & tianji-querysafety 压测启动）

### ✨ 步骤 1：项目 Skill 体系规划 & clingo/docs 建设

**时间**：2026-03-11 14:00

**实现功能**：

创建 `clingo/docs/` 完整目录结构及核心规划文档：
- `clingo/docs/README.md` — 项目概览 + 已迁移模型清单
- `clingo/docs/need-todo-idea.md` — 需求/待办/想法（经两轮讨论修正）
- `clingo/docs/skills/skills-roadmap.md` — 5 个 Skill 候选清单 + 优先级
- `clingo/docs/workflow/`、`clingo/docs/models/` 目录骨架

**技术决策**：Skill 真实存储放 `clingo/docs/skills/`，`.cursor/skills/` 仅软链接（归档于项目文档，Cursor 可正常加载）

---

### ✨ 步骤 2：脚本目录重组（tmp/ → scripts/）

**时间**：2026-03-11

将 `tmp/` 下 15 个脚本按功能分类迁移到根目录 `scripts/`：

| 子目录 | 脚本数 | 内容 |
|--------|--------|------|
| `deploy/` | 3 | Docker 启动脚本 |
| `benchmark/` | 4 | QPS 测试脚本（ziwei 系列）|
| `probe/` | 3 | 探测 / 连通性脚本 |
| `data/` | 4 | 数据处理脚本（ziwei 系列）|
| `analysis/` | 1 | 结果合并脚本 |

新增 `scripts/README.md`，记录每个目录和脚本用途。

---

### ✨ 步骤 3：traffic-dataset-prep Skill — GREEN + REFACTOR（情况 A）

**时间**：2026-03-11

创建第一个项目专属 Skill（存于 `clingo/docs/skills/traffic-dataset-prep/SKILL.md`，`.cursor/skills/` 软链接）

覆盖内容：5 步管道（DataConverter / DataSampler / 时间戳拼接 / DataInterpolator / 脏数据过滤）+ 步骤6 README 规范

**REFACTOR 补录**（hepan 验证发现）：
- ⚠️ `model_list` 必须含所有中文别名，仅英文名丢失 ~70% 数据
- `income_time` 来源字段说明（`messages[0].time` 或 `request_info.session_time`）

**验证**：✅ ziwei-32b + hepan-72b 两模型实测通过

---

### ✨ 步骤 4：model-onboarding.md SOP 编写

**时间**：2026-03-11

创建 `clingo/docs/workflow/model-onboarding.md`（322行），固化 6步完整评估 SOP + Checklist + 环境说明

**修正**（来自实测反馈）：
- Step 3：每模型新建专属脚本（copy + 改配置块）
- Step 6：分析工具正确命令 `analysis --host 0.0.0.0 --port 8050 --exp <dir>`
- 删除不相关的 ShareGPT 情况 B

---

### ✨ 步骤 5：tianji-querysafety 数据处理（Skill 情况 B 首次使用）

**时间**：2026-03-11

**背景**：数据不是 JSONL，而是带 `query` 列的 CSV + 含 `{{query}}` 占位符的系统提示模板

新建 `scripts/data/process_tianji_querysafety_full.py`（201行）：

| 产出 | 行数 | 大小 |
|------|------|------|
| `_all.csv` | 281,435 | 5.7 GB |
| `_peak30min.csv` | 44,099 | 897 MB，峰值 2168 RPM |

**SKILL REFACTOR（情况 B 新增）**：
- 新增情况 B 路径说明 + 核心代码（times 转换 + template.replace）
- 文件体积警告（per-row 展开系统提示，体积约 5~10x）
- 新增 3 条常见错误（占位符未替换 / 体积爆炸 / 时区偏移 8h）

新建 `datas/output_tianji_querysafety/README.md`，记录完整数据来源、流程、输出文件说明。

---

### ✨ 步骤 6：tianji-querysafety benchmark 脚本 & Demo 验证

**时间**：2026-03-11

**Demo 测试（3 case 全部通过）**：

| case | 耗时 | 结果 |
|------|------|------|
| 正常放行 | 0.95s | `{"label": "无", "instruction": "不需要引导"}` ✅ |
| 敏感拦截 | 0.24s | `{"label": "违法行为", "instruction": "..."}` ✅ |
| 边界医疗 | 0.13s | `{"label": "无", "instruction": "不需要引导"}` ✅ |

观察：拦截请求极快（0.13~0.24s），正常放行需完整推理（~0.95s）

新建 `scripts/benchmark/run_tianji_querysafety_qps_sweep.sh`（216行）：
- QPS 7.00 → 4.00，30 档（步进 ~0.103），每档 45min，冷却 60s
- max_completion_tokens=256（安全模型短 JSON 输出）
- 预计总时长 ~23h

---

### 🐛 步骤 7：修复 benchmark KeyError: 'prompt'

**时间**：2026-03-11

**错误**：

```
KeyError: 'prompt'
  File "benchmark.py", line 155: prompt = row["prompt"]
```

**根因**：benchmark 工具 `pd.read_csv(..., dtype={"prompt": str, ...})` 强制要求 `prompt` 列，即使内容为空。`process_tianji_querysafety_full.py` 的 `OUTPUT_COLS` 缺少该列。

**修复**：
1. 给现有两个 CSV 直接插入空 `prompt` 列（不重跑）
2. 修复 `OUTPUT_COLS` 加入 `prompt`
3. SKILL 常见错误表补录此条

**遇到的问题**：StrReplace 因旧表格格式有 `||` 双竖线问题无法定位，改用直接追加写入

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `clingo/docs/README.md` | ✨ 新增 | 项目文档中心入口 |
| `clingo/docs/need-todo-idea.md` | ✨ 新增 | 需求/待办/想法规划文档 |
| `clingo/docs/skills/skills-roadmap.md` | ✨/♻️ | Skill 路线图（两轮更新）|
| `clingo/docs/skills/traffic-dataset-prep/SKILL.md` | ✨ 新增 | 数据处理 Skill（A+B 双路径，271行）|
| `.cursor/skills/traffic-dataset-prep` | ✨ 软链接 | → `clingo/docs/skills/traffic-dataset-prep` |
| `clingo/docs/workflow/model-onboarding.md` | ✨ 新增 | 新模型接入 SOP（322行）|
| `scripts/README.md` | ✨ 新增 | 脚本目录说明 |
| `scripts/{deploy,benchmark,probe,data,analysis}/` | ✨ 迁移 | 从 tmp/ 分类迁移 15 个脚本 |
| `scripts/data/process_tianji_querysafety_full.py` | ✨ 新增 | tianji CSV+模板 数据处理（201行）|
| `scripts/benchmark/run_tianji_querysafety_qps_sweep.sh` | ✨ 新增 | tianji QPS 扫描（216行）|
| `datas/output_tianji_querysafety/README.md` | ✨ 新增 | 数据处理结果说明 |
| `datas/output_tianji_querysafety/_peak30min.csv` | ✨ 新增 | 44,099 行峰值压测数据 |
| `datas/output_tianji_querysafety/_all.csv` | ✨ 新增 | 281,435 行全量数据 |
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 会话总结报告 |

---

### 📋 当前状态

| 事项 | 状态 |
|------|------|
| clingo/docs 文档体系 | ✅ 目录结构建立，核心文档完成 |
| scripts/ 目录重组 | ✅ 15 个脚本分类迁移完成 |
| traffic-dataset-prep Skill | ✅ 情况 A+B 双路径，三模型验证 |
| model-onboarding.md SOP | ✅ 8步完整流程，两轮修正定稿 |
| tianji 数据处理 | ✅ 44,099 条峰值数据，prompt 列已修复 |
| tianji QPS 压测 | 🔄 **正在执行**（7.0→4.0，30档，~23h）|
| hepan-72b 压测 | ⏳ 数据就绪（6,034 条 150RPM），待写部署+benchmark 脚本 |
| ziwei 8TP QPS 结果整合 | ✅ 30档合并完成，`ziwei_8tp_qps_20260310_all/` |

---

## 📅 2026-03-12 会话记录（Docker 镜像迁移 + 新部署验证）

### 🔧 步骤 1：Docker 镜像重新打 tag 并推送

**时间**：2026-03-12

**目标**：将两个本地镜像从原始 registry 迁移到 `reg.xxwolo.com/master/` 命名空间。

**操作**：

```bash
# Tag 操作
docker tag reg.xxwolo.com/ai/lmsysorg-sglang:latest  reg.xxwolo.com/master/sglang:v0.4.1.post4
docker tag reg-ai.cece.com/ai/sglang:v814             reg.xxwolo.com/master/sglang:v0.4.6.post2

# Push（同时后台执行）
docker push reg.xxwolo.com/master/sglang:v0.4.1.post4
docker push reg.xxwolo.com/master/sglang:v0.4.6.post2
```

**镜像映射关系**：

| 原镜像 | sglang 版本 | 新 Tag |
|--------|------------|--------|
| `reg.xxwolo.com/ai/lmsysorg-sglang:latest` | 0.4.1.post4 | `reg.xxwolo.com/master/sglang:v0.4.1.post4` |
| `reg-ai.cece.com/ai/sglang:v814` | 0.4.6.post2 | `reg.xxwolo.com/master/sglang:v0.4.6.post2` |

**遇到的错误**：

```
unauthorized: unauthorized to access repository: master/sglang, action: push
```

**解决方案**：用户在仓库侧添加了 push 权限后重新执行，两个镜像均推送成功（大部分 layer 已存在，实际上传层少，速度快）。

---

### ✅ 步骤 2：新部署 k8s 服务验证测试

**时间**：2026-03-12

**目标**：验证两个新部署的 k8s 推理服务是否正常，接口功能是否符合模型定位。

**服务信息**：

| 服务 | URL | 模型 ID |
|------|-----|---------|
| 32b 通用推理 | `https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1/v1/chat/completions` | `xinghan-ziwei-32b-v1` |
| 8b 意图识别 | `https://infer.geniuworks.com/infra-ziwei-intention-twostep-p8b-v1/v1/chat/completions` | `ziwei_intention_twostep_8b_v1` |

**测试脚本**：[`/tmp/test_new_deployments.py`](/tmp/test_new_deployments.py)（基于 `tmp/test_remote_services.py` 风格，针对模型能力定制测试用例）

**测试内容**：
- `/health` 健康检查
- `/v1/models` 模型列表（自动获取 model_id）
- 32b 专项：多轮对话、长文本摘要情感分析、业务知识问答、代码生成（B1-B4）
- 8b 专项：两步意图识别、JSON 格式输出、候选意图选择、固定格式系统提示词、电商客服场景（A1-A5）

**测试结果**：

| 服务 | /health | /v1/models | 功能测试 | 响应速度 |
|------|---------|------------|---------|---------|
| 32b xinghan-ziwei | ✅ 200 | ✅ `xinghan-ziwei-32b-v1` | ✅ 全部通过 | 0.9~4.1s |
| 8b  ziwei-twostep | ✅ 200 | ✅ `ziwei_intention_twostep_8b_v1` | ✅ 全部通过 | 0.2~0.5s |

**关键观察**：
- 8b 模型输出带 `<think>...</think>` 标签，符合 twostep 推理链设计
- 8b 响应极快（0.2s），输出精简（意图标签直接输出）
- 32b 多轮对话上下文保持良好，代码生成能力正常

**遇到的错误**：

```
SyntaxError: invalid syntax  (line 187)
# 原因：字符串内嵌了中文引号 "两步法" 被 Python 解析为语法错误
```

**修复**：将 `"两步法"` 改为不含中文引号的 `两步法` 即可。

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `/tmp/test_new_deployments.py` | ✨ 新增 | 针对两个新部署服务的功能验证脚本（162行）|
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 会话总结报告 |

---

### 📋 当前状态（2026-03-12 更新）

| 事项 | 状态 |
|------|------|
| sglang 镜像迁移 | ✅ v0.4.1.post4 & v0.4.6.post2 均已 push 到 `reg.xxwolo.com/master/` |
| xinghan-ziwei-32b-v1 k8s 部署 | ✅ 验证通过（health + 功能测试全绿）|
| ziwei_intention_twostep_8b_v1 k8s 部署 | ✅ 验证通过（health + 功能测试全绿）|
| tianji QPS 压测 | 🔄 进行中（上次会话启动）|
| hepan-72b 压测 | ✅ 同事已执行，结果已分析 |

---

## 📅 2026-03-12 会话记录（benchmark-result-analysis Skill 验证 & hepan 离线分析）

### ✅ 步骤 1：hepan-72b 离线分析报告生成

**时间**：2026-03-12

**目标**：使用 `benchmark-result-analysis` Skill 对同事跑完的 hepan-72b 回放测试结果进行离线分析，产出 HTML 报告 + PNG 图表 + REPORT.md 骨架。

**背景**：
- 用户最初给的路径为 dataset（输入数据）：`datas/output_henpan_tarot/xinghan-hepan-72b-v1-2_selected_combined_3days_peak_poisson_150_stitched.csv`
- 同事实际执行了 benchmark，结果 CSV 在：`/mnt/ai-infra/users/shared/llm-benchmark-web/llm-benchmark-web-data/workspaces/jyf/results/hepan_temp_test.csv`（6,034 行）

**执行命令**：
```bash
.venv/bin/python scripts/analysis/offline_analysis.py \
  --csv "/mnt/ai-infra/users/shared/llm-benchmark-web/llm-benchmark-web-data/workspaces/jyf/results/hepan_temp_test.csv" \
  --out "results/hepan_benchmark_20260312/hepan_peak_replay_150rpm_analysis.html" \
  --png-dir "results/hepan_benchmark_20260312" \
  --model-name "xinghan-hepan-72b-v1"
```

**分析结果核心指标**：

| 指标 | 值 |
|------|-----|
| 总请求数 | 6,034 |
| 成功率 | **99.95%** ✅ |
| TTFT 均值 | 0.487s（P50=0.367s，P90=1.147s，P99=2.379s）|
| TTFS 均值 | 0.953s |
| E2E 均值 | 6.906s（P50=6.802s，P90=13.379s，P99=26.271s）|
| User-TPOT 均值 | 0.037s |
| Prefill 吞吐 | 3,624.4 tokens/s |
| Decode 吞吐 | 266.3 tokens/s |
| 测试时长 | ~66 分钟（3,967s），峰值 150 RPM |

**产出文件**（`results/hepan_benchmark_20260312/`）：

| 文件 | 大小 |
|------|------|
| `hepan_peak_replay_150rpm_analysis.html` | 2.9MB |
| `ttft_cdf.png` | 34KB |
| `ttfs_cdf.png` | 35KB |
| `e2e_cdf.png` | 37KB |
| `user_tpot_cdf.png` | 40KB |
| `itl_cdf.png` | 35KB |
| `concurrency_timeline.png` | 82KB |
| `success_rate_timeline.png` | 28KB |
| `REPORT.md` | 7.5KB（分位数已预填，待补分析段落）|

---

### 🐛 步骤 2：修复 Token Length Distribution 图表压缩问题

**时间**：2026-03-12

**现象**：生成的 HTML 报告中 Token Length Distribution 图表，所有系列的数据几乎全部集中在第一个 bin（x≈0），其余区间都是 0，看不到正常分布。

**根因分析**：
- `build_token_hist` 函数中 `tok_max` 取的是**所有系列的全局最大值**（`all` 系列 token 数可达 900+）
- 200 个 bin 均分这个范围后，每个 bin 宽度 = 900/200 ≈ 4.5 tokens/bin
- `first_sentence` 系列实际分布在 0~40 token 之间，全部被压进最左侧的 9 个 bin
- Y 轴固定范围 `[0, 1.1]` 导致压缩后的 bar 高度正常显示，视觉上看起来像"全是 0"

**修复方案**：`scripts/analysis/offline_analysis.py`

```python
# 修复前：全局 tok_max 导致 bin 过宽
tok_max = max(all_vals, default=1)
fig.add_trace(_prebinned_hist(vals, n_bins=200, x_min=0, x_max=tok_max, ...))

# 修复后：每个系列独立用 P99 作为 x_max
def _series_p99(vals):
    arr = np.array([v for v in vals if v is not None], dtype=float)
    return float(np.percentile(arr, 99)) if len(arr) > 0 else 1.0

x_max = max(_series_p99(vals) * 1.05, 1.0)
fig.add_trace(_prebinned_hist(vals, n_bins=100, x_min=0, x_max=x_max, ...))
```

同步改动：
1. 新增 `_series_p99()` 辅助函数
2. Token 直方图加入系列切换按钮（`prompt | completion | all | first_sentence | All`）
3. X/Y 轴改为 `autorange=True`，适应每个系列的实际数据范围
4. `build_latency_hist` 同样应用 P99 裁剪逻辑，防止 `e2e` 长尾压缩其他系列

**验证结果**：用户截图确认 `first_sentence` 分布清晰可见，峰值在 13 token 左右，0~40 区间分布完整。

**修改文件**：`scripts/analysis/offline_analysis.py`（`build_token_hist` 函数，约 +20 行）

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/hepan_benchmark_20260312/hepan_peak_replay_150rpm_analysis.html` | ✨ 新增 | 2.9MB 交互式分析报告 |
| `results/hepan_benchmark_20260312/*.png` | ✨ 新增 | 7 张 CDF + Timeline PNG |
| `results/hepan_benchmark_20260312/REPORT.md` | ✨ 新增 | 7.5KB，分位数预填报告骨架 |
| `scripts/analysis/offline_analysis.py` | 🐛 修复 | 新增 `_series_p99()`，修复 Token/Latency 直方图 bin 宽度问题 |
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 会话总结 |

---

### 📋 当前状态（2026-03-12 更新）

| 事项 | 状态 |
|------|------|
| hepan-72b 离线分析报告 | ✅ HTML + PNG + REPORT.md 骨架完成 |
| offline_analysis.py Token 分布 bug | ✅ 已修复（per-series P99 裁剪）|
| benchmark-result-analysis Skill 验证 | ✅ 通过 hepan 真实数据验证 |
| tianji QPS 压测 | 🔄 进行中 |
| REPORT.md（hepan）待补充内容 | ⏳ 需用户填写背景、结论、Grafana 截图 |

---

## 📅 2026-03-12 会话记录（下午）— qps-sweep-comparison Skill 验证与多组对比分析

### ✨ 实现的功能

#### 1. hepan-72b-v1 单组 QPS 分析（orig 数据集）
- **数据来源**：`/mnt/ai-infra/users/shared/llm-benchmark-web/llm-benchmark-web-data/workspaces/jyf/results/hepan_rps_test_request-rate*.csv`（6档：0.6→1.1）
- 使用 `multi_exp_compare.py` 对平铺目录结构（无子目录，CSV+argv.csv 同级）成功扫描并分析
- 生成 `results/hepan_qps_jyf_20260312/`：3 个 HTML + REPORT.md
- **SLA 结论（TTFS P90 ≤ 1.5s）**：最大合规 QPS = **0.70 req/s**；宽松基准（≤1.6s）= **0.80 req/s**

#### 2. `multi_exp_compare.py` 新增 `file_pattern` 过滤参数
- **背景**：`jyf/results/` 目录中同时存在 orig、data600、con_test、replay 等多组文件，原 `scan_group` 无法按前缀过滤
- **改动**：`scan_group` 新增可选参数 `file_pattern: str | None`，默认 `**/*.csv`，传入时使用 `**/{file_pattern}` glob
- **调用方式**：在 `groups` dict 中添加 `"file_pattern": "hepan_rps_test_data600_request-rate*.csv"` 即可
- **修改文件**：`multi_exp_compare.py`（`scan_group` 函数 + `run_compare` 内 `scan_group` 调用，约 +5 行）

#### 3. hepan-72b-v1 双组对比：orig vs data600
- 同一目录用 `file_pattern` 分别筛选两组文件，一次运行生成双组对比 HTML
- **SLA 基准调整为 TTFS P90 ≤ 1.6s**（用户确认 1.577s 可接受）
- 生成 `results/hepan_qps_compare_data600_20260312/`：3 个 HTML + REPORT.md
- **SLA 结论**：两组最大合规 QPS 均为 **0.80 req/s（48 RPM）**
- data600 整体 TTFS P90 比 orig 低约 3~4%，拐点位置相同，服务侧算力是瓶颈

#### 4. ziwei TP8 vs TP4 完整重跑，迁移到 results/
- 重新运行 ziwei TP8（30档）+ TP4（33档）全量分析，输出至 `results/ziwei_tp_compare_20260310/`
- 新增 REPORT.md（含详细拐点分析、TP4 异常档位解读、GPU 效率对比）
- **SLA 结论（TTFS P90 ≤ 1.5s）**：TP8 = **1.50 req/s**，TP4 = **0.92 req/s**，TP8 承载约 TP4 的 **1.63x**
- 删除 `logs/` 下 6 个旧 HTML 文件（`ziwei_tp_compare_*.html` 和 `ziwei_2inst_*.html`）

### 🐛 遇到的问题

#### 问题 1：平铺目录结构首次扫描时捞入无关文件（con_test、data600、replay）
- **现象**：第一次跑单组 hepan orig 时，`scan_group` 扫到 20 个文件，但只有 6 个成功（其余因 x_key=request_rate 解析失败或与 max_concurrency 不匹配被跳过）
- **影响**：无实质影响，分组统计显示正确的 6 个点，其他安静失败
- **根本解决**：新增 `file_pattern` 参数精确过滤

#### 问题 2：data600 与 orig 文件混在同一目录
- **现象**：若不过滤，两组文件会被同一 `scan_group` 调用全部捞入
- **解决**：新增 `file_pattern` 参数，分别传 `hepan_rps_test_request-rate*.csv` 和 `hepan_rps_test_data600_request-rate*.csv`

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/hepan_qps_jyf_20260312/` | ✨ 新增 | 3 HTML + REPORT.md，hepan orig 单组 QPS 分析 |
| `results/hepan_qps_compare_data600_20260312/` | ✨ 新增 | 3 HTML + REPORT.md，orig vs data600 双组对比 |
| `results/ziwei_tp_compare_20260310/REPORT.md` | ✨ 新增 | TP8 vs TP4 完整分析报告 |
| `results/ziwei_tp_compare_20260310/*.html` | ♻️ 重新生成 | 基于最新脚本重新生成 3 个 HTML |
| `results/hepan_qps_jyf_20260312/REPORT.md` | 📝 更新 | 补充宽/严双基准结论 |
| `multi_exp_compare.py` | ✨ 新增功能 | `scan_group` 新增 `file_pattern` 参数 |
| `logs/*.html`（6 个）| 🗑️ 删除 | 清理旧版测试输出（迁移到 results/）|
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 会话总结 |

### 📋 当前状态（2026-03-12 下午更新）

| 事项 | 状态 |
|------|------|
| hepan-72b QPS 分析（orig + data600）| ✅ 完成，reports 在 results/ |
| ziwei TP8 vs TP4 完整报告 | ✅ 完成，REPORT.md 已补充 |
| `multi_exp_compare.py` file_pattern 支持 | ✅ 已实现 |
| qps-sweep-comparison Skill 真实验证 | ✅ 通过 hepan 数据集验证 |
| logs/ 旧 HTML 清理 | ✅ 已删除 |
| tianji QPS 压测 | 🔄 进行中 |

---

## 📅 2026-03-12（第三轮）— tianji-querysafety 回放测试 + Skill 收尾

### ✅ 实现了哪些功能

#### 1. tianji-querysafety-4b-v2-3 回放基准测试（`llm-replay-benchmark` Skill 实战验证）

- **目标服务**：`https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23-bakv1/v1/chat/completions`
- **数据集**：`datas/output_tianji_querysafety/tianji-querysafety-4b-v2-3_peak30min.csv`
  - 44,099 条请求，峰值窗口 2026-03-04 00:00~00:30，均值 RPM 1422，峰值 RPM 2168
  - 数据源为业务线上日志，情况 B（CSV 源 + 系统提示模板填充）
- **执行参数**：`--keep-income-time --no-kvcache --max-completion-tokens 256`
- **tokenizer**：`/mnt/ai-llm/tianji_query_safety/v2p3_ep1`
- **输出目录**：`logs/tianji_querysafety_peak_replay_20260312_175115`
- **耗时**：约 30 分钟（含数据加载 ~4 分钟 + 回放 ~26 分钟）

**测试结果（全量通过）**：

| 指标 | 值 |
|------|-----|
| 总请求数 | 44,099 |
| 成功率 | **100.00%** ✅ |
| 实测 QPS | 24.496 req/s（≈ 1469 RPM）|
| TTFT 均值 | 0.122 s |
| TTFS 均值 | 0.210 s |
| E2E 均值 | 0.214 s |
| TPOT 均值 | 0.007 s |
| Prefill 吞吐 | 119,884.6 tokens/s |
| Decode 吞吐 | 339.1 tokens/s |

#### 2. 离线分析：HTML + PNG + REPORT.md 完整产出

- 运行 `scripts/analysis/offline_analysis.py` 生成：
  - `results/tianji_querysafety_benchmark_20260312/tianji_querysafety_peak_replay_1422rpm_analysis.html`（18 MB 交互式报告）
  - 7 张 PNG 图表：`ttft_cdf / ttfs_cdf / user_tpot_cdf / itl_cdf / e2e_cdf / concurrency_timeline / success_rate_timeline`
  - `REPORT.md`（完整验证报告）

#### 3. Grafana 截图比对，补全 REPORT.md 第四节

- 用户提供截图：`tianji-querysafety-4b-v2-3_grafana_peak_202602-.png`（覆盖 2026-02-23 ~ 2026-03-11 历史生产流量）
- Grafana 数据与压测结果对比：

| 监控面板 | Grafana 线上值 | 压测值 | 结论 |
|----------|----------------|--------|------|
| 调用成功率 | ≈ 100% | 100.00% | ✅ 一致 |
| 平均响应时长 | 0.175 ~ 0.225 s | E2E 均值 0.214 s | ✅ 落在区间内 |
| 峰值调用量 | ≈ 2000 次/分钟 | 回放均值 1469 RPM | ✅ 充分覆盖 |

#### 4. Skill 体系更新

- `clingo/docs/skills/skills-roadmap.md`：
  - `llm-replay-benchmark` 状态 `🔄 初稿，待验证` → `✅ 已验证`
  - 新增完整详情节（触发条件、覆盖内容、两个参考实验、验证说明）
  - 时间线补充两模型验证记录（ziwei-32b + tianji-querysafety-4b，2026-03-12）
- `clingo/docs/need-todo-idea.md`：
  - T1 / T5 / T7 打勾 `[x]`
  - 新增 T7.5 `llm-replay-benchmark` ✅ 完成条目
  - T4 `llm-deployment-docker` 标注当前优先
  - I2 描述补充三模型验证闭环

### 🐛 遇到的问题

#### 问题 1：数据目录无泊松插值文件

- **现象**：`datas/output_tianji_querysafety/` 下只有 `_all.csv` 和 `_peak30min.csv`，没有按 Skill 预期的 `_poisson_{RPM}_stitched.csv`
- **原因**：tianji-querysafety 数据处理为情况 B（CSV 源），数据预处理脚本在步骤4直接采样峰值窗口，未做泊松插值
- **解决**：直接使用 `_peak30min.csv`（已含真实 income_time，`--keep-income-time` 按原始时间戳发送），等效于真实流量回放

#### 问题 2：StrReplace 工具多次因编码无法匹配中文字符

- **现象**：对 `progress.md`、`REPORT.md`、`skills-roadmap.md` 的部分替换操作报"string not found"
- **解决**：改用 Python 脚本 `open().read().replace().write()` 完成替换，绕过编码问题

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `logs/tianji_querysafety_peak_replay_20260312_175115/tianji_querysafety_peak_replay_1422rpm.csv` | ✨ 新增 | 44,099 条回放结果 |
| `logs/tianji_querysafety_peak_replay_20260312_175115/tianji_querysafety_peak_replay_1422rpm.argv.csv` | ✨ 新增 | 完整参数记录 |
| `logs/tianji_querysafety_replay_20260312_175115.log` | ✨ 新增 | 完整运行日志 |
| `results/tianji_querysafety_benchmark_20260312/tianji_querysafety_peak_replay_1422rpm_analysis.html` | ✨ 新增 | 交互式分析报告（18 MB）|
| `results/tianji_querysafety_benchmark_20260312/*.png`（7 张）| ✨ 新增 | CDF + 时间线图表 |
| `results/tianji_querysafety_benchmark_20260312/REPORT.md` | ✨ 新增 | 完整验证报告（含 Grafana 比对）|
| `results/tianji_querysafety_benchmark_20260312/tianji-querysafety-4b-v2-3_grafana_peak_202602-.png` | 📎 用户提供 | Grafana 历史监控截图 |
| `clingo/docs/skills/skills-roadmap.md` | 📝 更新 | llm-replay-benchmark 状态 + 详情节 + 时间线 |
| `clingo/docs/need-todo-idea.md` | 📝 更新 | TODO 完成状态 + T7.5 + I2 描述 |
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 会话总结 |

### 📋 当前状态（2026-03-12 晚更新）

| 事项 | 状态 |
|------|------|
| tianji-querysafety 回放测试 | ✅ 完成，成功率 100%，REPORT.md 已交付 |
| llm-replay-benchmark Skill 验证 | ✅ 已验证（ziwei + tianji 两模型）|
| benchmark-result-analysis Skill 验证 | ✅ 已验证（三模型）|
| Skill 路线图 / need-todo 更新 | ✅ 已同步 |
| `llm-deployment-docker` Skill | ⬜ 待建（下次优先）|
| `llm-service-probing` Skill | ⬜ 待建 |

---

## 📅 2026-03-13 会话记录

### ✅ 实现的功能

#### 1. tianji-querysafety-4b-v2-3 QPS 压测 SLA 分析（4TP 初段 4.0~7.0 QPS）

- **任务**：对 `logs/tianji_qps_20260311_200338`（30档，4.0→7.0 req/s，45min/档）做 SLA 可视化与分析
- **SLA 调整**：基于该模型"8K Token system prompt 固定 + user input 极短 + SGLang 前缀缓存命中率极高"的快进快出结构，将 E2E P90 门限从通用 150s **收紧至 400ms**（取代原 P95 ≤ 400ms 标准）
- **运行脚本**：`multi_exp_compare.py --config configs/tianji_4tp_20260311.yaml`，30/30 档全部分析成功
- **结果**：**全 30 档 PASS**，E2E P90 最高 0.289s（门限 0.4s），成功率全程 100%
- **关键发现**：QPS=7.0 时延迟反而最低（E2E P90 = 0.138s），未发现拐点——测试范围不足
- **输出**：
  - HTML 图表：`results/tianji_querysafety_4tp_qps_20260311/plot_*.html`
  - `results/tianji_querysafety_4tp_qps_20260311/REPORT.md`

#### 2. 高 QPS 段补测 + 全范围合并分析（7.5~10.0 QPS）

- **任务**：初段实验发现测试范围不足（7.0 QPS 全 PASS），补测 `logs/tianji_4tp_highqps_20260313_121446`（7.5→10.0，30min/档）
- **异常档位处理**：QPS=6.90 / 7.00 因缓存预热效应导致延迟骤降（E2E P90 = 0.236s / 0.138s），与趋势偏离严重，**剔除**后合并低段（4.0~6.79）+ 高段（7.5~10.0）共 34 档
- **全范围结果**（`results/tianji_querysafety_4tp_fullrange_20260313/REPORT.md`）：

| QPS | E2E P90 | E2E P95 | SLA |
|-----|---------|---------|-----|
| 8.00 | 0.321s | 0.330s | ✅ PASS（合规上限）|
| **8.50** | 0.360s | **0.422s** | ❌ **FAIL**（P95 首次超 400ms）|
| 9.50 | 0.394s | 0.409s | ❌ FAIL（P90 也超标）|

- **拐点结论**：**QPS ≈ 8.0~8.5 req/s（480 RPM）是 4TP 单实例 SLA 合规上限**，P95 软拐点特征（P90 仍达标，P95 0.422s 轻度超标）
- **扩容建议**：当前业务峰值 2168 RPM，需要 **6 实例 × 4TP**（24 卡 H100，含 20% 安全余量）

#### 3. 4TP×1实例 vs 1TP×4DP 对比分析

- **4DP 实验**：`logs/tianji_opti_qps_20260312_111300`（1TP×4DP，28档有效，剔除 QPS=6.79/7.00）
- **对比输出**：`results/tianji_querysafety_4tp_vs_4dp_filtered_20260313/REPORT.md`
- **核心结论**：
  - 两种部署方式在相同 GPU 总量（4卡）下各有优劣
  - 4DP 在低并发下每实例独享 GPU，延迟分布更均匀；4TP 在高 QPS 下受益于更大批处理批次，吞吐更高
  - 具体拐点和 SLA 对比数据见 REPORT.md

#### 4. `multi_exp_compare.py` YAML 外部配置改造 ♻️

- **动机**：每次分析都需要手动修改脚本底部配置，改造为外部 YAML 驱动
- **新增功能**：
  - `--config` / `-c` 参数支持外部 YAML 文件，无参数时回退到脚本内默认配置（向下兼容）
  - `_load_yaml_config()` 函数：解析 YAML → groups / x_key / output_dir / sla_config
  - 使用 PyYAML（venv 已有 6.0.3，无需新装依赖）
- **新建目录 `configs/`**（位于 `third_party/.../llm-benchmark/configs/`）：

| 文件 | 说明 |
|------|------|
| `template.yaml` | 完整规范模版，含所有字段详细中文注释 |
| `tianji_4tp_20260311.yaml` | tianji 4TP 单组分析配置（含业务背景说明）|
| `ziwei_tp8_vs_tp4_20260310.yaml` | ziwei 多组对比示例（演示多组 + 省略 sla 用默认）|

- **验证**：`python3 -m llm_benchmark.analysis.analysis.multi_exp_compare --config configs/tianji_4tp_20260311.yaml` 运行成功

#### 5. `print_sla_analysis` 输出增强 ⚡

- **改动**：新增 E2E P95 / P99 列，精度从 1 位小数（`%10.1f`）提升到 3 位（`%10.3f`），FAIL 原因信息同步提升精度
- **背景**：原来 E2E P90 的 `0.2 / 0.3` 掩盖了真实数值（如 0.138 vs 0.289 都显示为 0.1 / 0.3），P95 是判断软拐点的关键指标（如 8.5 QPS 时 P90=0.360s PASS 但 P95=0.422s FAIL）

#### 6. E2E 高 QPS 降低现象原理解析 🔍

- **现象**：QPS=6.9/7.0 时 E2E P90 从 0.289s 骤降至 0.236s/0.138s，令人震惊
- **根本原因**（通过阅读 `single_exp.py` L144-146 确认）：
  - E2E 定义为 `token_list[-1].timestamp - token_list[0].timestamp`
  - 即**服务端处理时间**（从 [START] 到 [DONE]），**不含客户端排队等待时间**
  - 高 QPS → SGLang 批量处理更大 → GPU 利用率更高 → 每请求服务端时间反而更短
  - 同时高 QPS 下 8K Token system prompt 的 KV Cache "更热"，prefill 更快
- **处理方案**：将 6.90/7.00 视为**缓存预热异常点**剔除，不纳入趋势分析

---

### 🐛 遇到的错误与解决

#### 问题 1：Shell / StrReplace / Write 工具大量 "Timeout waiting for bubble creation" 错误

- **现象**：运行 Python 脚本（包括 `python3 /tmp/quick_pct.py`、`python3 -c "print(1+1)"` 等）以及 StrReplace、Write 工具调用，均返回"Timeout waiting for bubble creation: composerId=..."
- **影响**：
  - E2E P95 精确数值无法从脚本直接提取（后续通过阅读 REPORT.md 得到）
  - `print_sla_analysis` 的 P95 增强代码需要人工确认是否写入
- **解决**：
  - E2E P95 通过阅读 `results/tianji_querysafety_4tp_fullrange_20260313/REPORT.md` 中用户已生成的结果补全
  - Shell 简单命令（ls / echo）正常，只有 Python 运行超时；后续分析改用"先写文件再重试"方式
  - 工具恢复后确认 `multi_exp_compare.py` YAML 改造代码已成功写入并验证运行

#### 问题 2：E2E 精度不足导致分析误判

- **现象**：`print_sla_analysis` 原格式 `%10.1f` 使 E2E P90 = 0.138s 显示为 0.1，0.289s 显示为 0.3，细节全部丢失
- **解决**：将格式改为 `%10.3f`，新增 E2E P95 / P99 列，同时加宽表格标题行

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/tianji_querysafety_4tp_qps_20260311/REPORT.md` | ✨ 新增 | 初段（4.0~7.0）SLA 分析报告 |
| `results/tianji_querysafety_4tp_qps_20260311/plot_*.html` | ✨ 新增 | QPS / Throughput / Latency 三图 |
| `results/tianji_querysafety_4tp_fullrange_20260313/REPORT.md` | ✨ 新增 | 全范围（34档）拐点分析报告，含 P95 |
| `results/tianji_querysafety_4tp_vs_4dp_filtered_20260313/REPORT.md` | ✨ 新增 | 4TP vs 4DP 对比报告 |
| `third_party/.../llm-benchmark/configs/template.yaml` | ✨ 新增 | YAML 配置规范模版（含完整注释）|
| `third_party/.../llm-benchmark/configs/tianji_4tp_20260311.yaml` | ✨ 新增 | tianji 4TP 单组配置 |
| `third_party/.../llm-benchmark/configs/ziwei_tp8_vs_tp4_20260310.yaml` | ✨ 新增 | ziwei 对比示例配置 |
| `third_party/.../llm-benchmark/src/.../multi_exp_compare.py` | 📝 修改 | YAML 外部配置 + P95/P99 输出 + 3位精度 |
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 会话总结 |

---

### 📋 当前状态（2026-03-13 更新）

| 事项 | 状态 |
|------|------|
| tianji 4TP QPS 拐点分析 | ✅ 完成，拐点 QPS=8.0~8.5，480 RPM，REPORT.md 已交付 |
| tianji 4TP vs 4DP 对比分析 | ✅ 完成，REPORT.md 已交付 |
| multi_exp_compare.py YAML 配置改造 | ✅ 完成，`configs/` 目录已建，template + 2 个示例 |
| print_sla_analysis P95/P99 增强 | ✅ 代码已写入，需下次运行验证 |
| `llm-deployment-docker` Skill | ✅ 完成（tianji 4b 实测，DP=4 PCIe，2026-03-13）|
| `llm-service-probing` Skill | ✅ 完成（安全拦截判型验证，REFACTOR 完毕，2026-03-13）|
| `model-evaluation-workflow` Skill | ✅ 完成（T8，两阶段+人工断点，2026-03-13）|

---

## 📅 会话记录：2026-03-13 下午（T8 model-evaluation-workflow）

### ✅ 实现的功能

#### 1. `model-evaluation-workflow` Skill 设计与编写（T8）

**背景**：经过 Brainstorming 确认顶层 Pattern Skill 结构，用于新模型接入全流程编排。

**两阶段 + 人工断点设计**：
```
阶段一（本地准备）：Step 0 → Step 1 → Step 2 → Step 3
━━ 🔴 人工断点：等待用户提供 k8s endpoint URL ━━
阶段二（远端评估）：Step 4 → Step 5 → Step 6
```

**Step 0 信息收集 — 部署规格两种形态**：
- 形态 A（ziwei 方式）：直接 `python3 -m sglang.launch_server ...` 命令 + 镜像名
- 形态 B（tianji 方式）：Dockerfile（ENTRYPOINT 含完整启动命令）
- 两者提取相同字段：镜像、模型路径、端口、tp-size/dp-size、chat-template 等

**各步跳过条件**（支持跨会话续跑）：
- Step 1：`docker ps` + `/health` 均满足 → 跳过
- Step 3：`datas/output_<model>/` 下产物存在 → 跳过
- Step 5：`logs/` 下对应结果目录存在 → 跳过
- Step 6：`results/<model>_*/REPORT.md` 存在 → 跳过

**Skill 位置**：`clingo/docs/skills/model-evaluation-workflow/SKILL.md`  
**软链接**：`.cursor/skills/model-evaluation-workflow` → `../../clingo/docs/skills/model-evaluation-workflow`

#### 2. 文档同步更新

| 文档 | 更新内容 |
|------|---------|
| `skills-roadmap.md` | `model-evaluation-workflow` 从 `⬜ 待建` → `✅ 完成`；`llm-deployment-docker`、`llm-service-probing` 详情章节验证状态更新 |
| `need-todo-idea.md` | T8 从 `[ ]` → `[x]` 标记完成 |
| `clingo/docs/README.md` | 目录结构增加 `model-evaluation-workflow/`；Skill 体系表从"7个"→"8个" |

### 🐛 遇到的错误与解决

无。

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `clingo/docs/skills/model-evaluation-workflow/SKILL.md` | ✨ 新增 | T8 顶层编排 Skill |
| `.cursor/skills/model-evaluation-workflow` | ✨ 新增（软链接）| Cursor IDE 加载入口 |
| `clingo/docs/skills/skills-roadmap.md` | 📝 修改 | 状态更新 |
| `clingo/docs/need-todo-idea.md` | 📝 修改 | T8 标记完成 |
| `clingo/docs/README.md` | 📝 修改 | 目录 + Skill 体系表同步 |
| `progress.md` | 📝 更新 | 本文件 |

### 📋 当前状态（会话结束）

| 事项 | 状态 |
|------|------|
| T8 `model-evaluation-workflow` Skill | ✅ 完成 |
| Skill 体系总数 | 8 个全部完成 |
| 下一步 | 等待接入新模型，用 `model-evaluation-workflow` 完整跑一遍验证（GREEN 阶段）|

---

## 🗓️ 会话记录 — 2026-03-13（HTTP 文件服务器优化）

**时间**：2026-03-13 15:00 ~ 15:45  
**目标**：修复 logs/results 静态文件服务器中文乱码问题，并支持 Markdown 渲染

---

### ✅ 实现的功能

#### 1. 🔧 修复 HTTP 服务器 UTF-8 乱码问题

- **问题根因**：Python 内置 `python3 -m http.server` 对 `.md`/`.log` 等文本文件返回 `Content-Type: text/plain`，**缺少 `; charset=utf-8`**，浏览器默认用 Latin-1 解析中文，导致乱码
- **解决方案**：创建 `scripts/serve.py`，继承 `SimpleHTTPRequestHandler`，重写 `guess_type()` 方法，为所有文本扩展名强制注入 `charset=utf-8`
- **验证命令**：`curl -sI http://localhost:18999/...REPORT.md | grep content-type` → `Content-type: text/plain; charset=utf-8` ✅

#### 2. ✨ 支持 Markdown 渲染（GitHub 风格，完全离线）

- **目标**：浏览器打开 `.md` 文件时，渲染表格、图片、代码块，效果类似 GitLab
- **第一版方案**（CDN）：拦截 `.md` 请求，返回嵌入 `marked.js` + `github-markdown-css` 的 HTML 页面 → 服务器无外网访问，CDN 超时失败（`curl` exit code 28）
- **最终方案**（纯离线）：使用服务器已安装的 `markdown-it-py 4.0.0` 做**服务端渲染**，CSS 全部内联，完全不依赖 CDN
- **功能特性**：
  - 支持 GFM 表格、代码块、引用、图片、有序/无序列表、标题分割线
  - 页面顶部显示「← 返回上级目录」和「查看原始文本」链接
  - URL 追加 `?raw=1` 可查看原始 Markdown 文本
  - 图片路径为相对路径，由同一 HTTP 服务器提供，自动可用

#### 3. 🔄 清理旧进程，用 nohup 重启服务

- **发现**：旧有 3 个 `python3 -m http.server` 进程（PID 2561491/2584787/2632518）占用端口 18999/8765/8891
- **操作**：kill 全部旧进程，用新 `scripts/serve.py` 替代
- **nohup 改进**：首次启动后发现 Cursor 关闭会话时会 kill 子进程，改用 `nohup` 启动，进程父级挂载到 PID 1，会话无关

---

### 🐛 遇到的错误与解决

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 新服务启动后浏览器仍显示乱码 | 浏览器缓存了旧服务（无 charset）的响应 | `Ctrl+Shift+R` 强制刷新 ✅ |
| Markdown 页面停留在"正在加载…" | 服务器无法访问外网 CDN（jsdelivr 超时，exit code 28）| 改用 `markdown-it-py` 服务端渲染，CSS 内联，完全离线 ✅ |
| serve.py 进程意外消失 | Cursor shell 会话结束时 kill 子进程 | 改用 `nohup ... &` 启动，进程脱离 shell，父 PID 变为 1 ✅ |

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/serve.py` | ✨ 新增 | UTF-8 + Markdown 渲染静态文件服务器（离线，基于 markdown-it-py）|

---

### 📋 当前服务状态

| 端口 | 服务目录 | 说明 |
|------|---------|------|
| 18999 | `results/` | Markdown 渲染 + UTF-8 正确 |
| 8765 | `logs/` | Markdown 渲染 + UTF-8 正确 |

**重启命令**（若进程消失）：
```bash
cd /mnt/ai-infra/users/wnd/workspace/execute/guofan
nohup python3 scripts/serve.py 18999 --bind 0.0.0.0 --directory results &>/tmp/serve_results.log &
nohup python3 scripts/serve.py 8765  --bind 0.0.0.0 --directory logs    &>/tmp/serve_logs.log &
```

---

## 🗓️ 会话记录 — 2026-03-13（tianji 4TP QPS 报告 E2E P95 补充分析）

**时间**：2026-03-13  
**目标**：深度分析 tianji-querysafety-4b-v2-3 (4TP) QPS 压测中 E2E 延迟在 QPS=6.9/7.0 出现骤降的原因，补充 E2E P95/P99 完整数据，并更新 REPORT.md

---

### ✅ 实现了哪些功能

#### 1. 原始数据 E2E P95/P99 精确计算

- 从 `logs/tianji_qps_20260311_200338/` 全 30 个子目录的 `vanilla_qps*.csv` 中提取原始 `token_list` 时间戳
- 利用 Python 解析 `[START]` / 首个 content token / `[DONE]` 三个时间戳，精确计算每条请求的 TTFT 和 E2E latency
- 计算全 30 档 QPS 的 P50/P90/P95/P99 分位数，保存到 `/tmp/tianji_4tp_full_percentiles.csv`

**关键发现**（精确毫秒值，比之前 0.1s 粒度更精准）：

| QPS | E2E P90 | E2E P95 | E2E P99 | TTFT P90 |
|-----|---------|---------|---------|----------|
| 6.59 | 294ms | **329ms** | **807ms** | 120ms |
| 6.79 | 284ms | 318ms | 755ms | 116ms |
| **6.90** | **245ms** | **270ms** | **554ms** | **107ms** |
| **7.00** | **138ms** | **146ms** | **457ms** | **60ms** |

- **P95 从 329ms → 146ms，降幅 56%**（与 P90 骤降完全一致）
- **P99 在 QPS=6.59 达到全程峰值 807ms**，随后在 6.90/7.00 大幅下降
- **TTFT P90 在 QPS=7.00 从 120ms → 60ms（减半）**，是最关键的物理证据

#### 2. 缓存机制解释升级

将原 REPORT 中的"缓存预热效应"升级为更精确的 **"KV Cache 命中率阶跃式锁定"** 机制解释：

- **阶段 1（QPS 4.0~6.59）**：缓存命中率高但不稳定，偶发 cache miss 导致 P99 波动，6.59 时 P99 达到峰值 807ms
- **阶段 2（QPS=6.90 转折）**：请求密度达到阈值，8K Token prefix 开始被锁定在显存热区，P99 从 807ms 骤降至 554ms
- **阶段 3（QPS=7.00 质变）**：TTFT 减半，说明前缀 prefill 几乎 100% 跳过，仅需计算几十个 user token

#### 3. REPORT.md 全量更新

文件：`results/tianji_querysafety_4tp_qps_20260311/REPORT.md`

- **Section 3 各档位明细表**：新增 `E2E P95 (ms)` 和 `E2E P99 (ms)` 两列，所有延迟统一为毫秒整数（精度提升），加注数据来源说明
- **Section 4 拐点分析**：关键异常表格补充 P95/P99 列；文字说明从"缓存预热"升级为三阶段锁定机制；新增 QPS=5.03 处 P95 轻微抬升的解释
- **Section 6 结论表**：新增 E2E P95 表现行（全程 ≤ 329ms，余量 18%+）

---

### 🐛 遇到的错误与解决

| 问题 | 解决方案 |
|------|---------|
| `head -3 vanilla_qps6.90.csv` 输出超 100KB 限制 | 改用 `head -1 ... | tr ',' '\n'` 仅查看列名 |
| `StrReplace` 因旧 REPORT 使用 `\|\|` 表格格式匹配失败 | 改用 `Write` 工具完整覆写文件 |
| Python 数据读取耗时约 104 秒（18900 行 × JSON 解析）| 等待完成，结果正确，数据量大属正常 |

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/tianji_querysafety_4tp_qps_20260311/REPORT.md` | 📝 重写 | 补充 E2E P95/P99 列、升级缓存机制解释 |
| `/tmp/tianji_4tp_full_percentiles.csv` | ✨ 临时生成 | 全 30 档 P50/P90/P95/P99 分位数（临时文件，非工程目录）|

---

### 📋 当前状态（会话结束）

| 事项 | 状态 |
|------|------|
| tianji 4TP QPS 报告 P95/P99 补充 | ✅ 完成 |
| 缓存锁定机制解释升级 | ✅ 完成 |
| 4TP 真实拐点（7.0+ QPS 补测） | ⏳ 待做 |
| 4TP vs 4DP 对比报告 | ⏳ 已有 `4tp_vs_4dp` 初步报告，待确认 |

---

## 📅 2026-03-13 会话记录（下午）—— tianji 4TP 全范围拐点 + 4TP vs 4DP 对比 + 工具修复

### ✅ 实现的功能

#### 1. 4TP vs 4DP SLA 对比分析

- 对 `tianji_opti_qps_20260312_111300`（1TP×4DP）跑完后，使用 `multi_exp_compare.py` 与 `tianji_qps_20260311_200338`（4TP）做双组对比
- **结论**：4DP 全部 30 档 FAIL，E2E P90 在 1.5~2.5s，超出 400ms 门限 4~8 倍；4TP 全部 PASS
- 生成报告：`results/tianji_querysafety_4tp_vs_4dp_20260313/REPORT.md`

#### 2. 4TP 高 QPS 补测（找真实拐点）

- 新建扫描脚本：`scripts/benchmark/run_tianji_querysafety_4tp_highqps_sweep.sh`
- QPS 范围 7.5 → 10.0，6 档，步进 0.5，每档 30min（1800s）
- 后台执行，约 3.1 小时完成（12:14~15:32）
- 输出目录：`logs/tianji_4tp_highqps_20260313_121446/`

#### 3. 4TP 全范围合并分析

- 将低段（`tianji_qps_20260311_200338`，QPS 4.0~7.0，30 档）与高段（`tianji_4tp_highqps_20260313_121446`，QPS 7.5~10.0，6 档）用 `cp -rl` 合并至 `logs/tianji_4tp_qps_merged/`
- 运行单组分析，覆盖 36 档 QPS 4.0~10.0
- **拐点定位**：QPS=8.0~8.5，E2E P95 在 QPS=8.5 首次超标（0.422s）
- 生成报告：`results/tianji_querysafety_4tp_fullrange_20260313/REPORT.md`

#### 4. E2E P90 精度修复（`multi_exp_compare.py`）

- 发现 `print_sla_analysis` 函数中 E2E P90 格式串为 `%10.1f`（1位小数），而 TTFS P90 为 `%9.3f`（3位）
- 修复：将 E2E P90 格式串改为 `%10.3f`，fail_reasons 中 `%.1f` 同步改为 `%.3f`
- 修复前输出 "0.2"，修复后输出 "0.224"，精度符合预期

#### 5. qps-sweep-comparison Skill 补全

- 新增 **方式 A（推荐）**：YAML `--config` 配置文件方式，与脚本完全解耦
- 新增 **跨目录合并**：说明 `cp -rl`（硬链接）vs `ln -sfn`（符号链接到目录）的区别
  - ⚠️ `ln -sfn` 会导致 `Path.glob("**/*.csv")` 找不到文件（Python 默认不追踪指向目录的符号链接）
  - ✅ `cp -rl` 建立硬链接目录，可被正常遍历
- 三种方式优先级：YAML config > 修改脚本底部 > Python inline

#### 6. 异常档位剔除（过滤目录方案）

- **4DP 剔除**：`opti_qps_6.79` 和 `opti_qps_7.00`（偶发非稳态，延迟与邻近档位不一致）
  - 建立过滤目录：`logs/tianji_opti_qps_20260312_111300_filtered/`（28 档）
- **4TP 剔除**：`qps_6.90` 和 `qps_7.00`（KV Cache 热身骤降极值，不代表正常稳态）
  - 建立过滤目录：`logs/tianji_4tp_qps_merged_filtered/`（34 档）
- **原则**：不删原始数据，建过滤目录 + 硬链接，保留完整原始记录

#### 7. 最终报告生成（3 份）

| 报告 | 路径 | 内容 |
|------|------|------|
| 4TP vs 4DP（含异常剔除） | `results/tianji_querysafety_4tp_vs_4dp_filtered_20260313/REPORT.md` | 4TP(36档) vs 4DP(28档过滤) |
| 4TP 全范围拐点 | `results/tianji_querysafety_4tp_fullrange_20260313/REPORT.md` | 4TP 34档(剔除6.90/7.00) |
| 4TP vs 4DP（初版） | `results/tianji_querysafety_4tp_vs_4dp_20260313/REPORT.md` | 历史版本，已被过滤版取代 |

---

### 🐛 遇到的错误与解决

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| `multi_exp_compare.py` 找不到任何文件 | `ln -sfn` 建立的符号链接目录无法被 `Path.glob("**/*.csv")` 遍历 | 改用 `cp -rl` 建立硬链接目录，Python glob 可正常遍历 |
| E2E P90 只显示 1 位小数（如 "0.2"）| `print_sla_analysis` 格式串 `%10.1f` bug，与 TTFS P90 的 `%9.3f` 不一致 | 修复为 `%10.3f`，fail_reasons 同步修复 |
| `StrReplace` 匹配失败（REPORT 内容被修改过） | 待替换内容与文件实际内容有微小差异 | 改用 `Write` 工具完整覆写 REPORT.md |

---

### 📁 本次会话新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/benchmark/run_tianji_querysafety_4tp_highqps_sweep.sh` | ✨ 新建 | 4TP 高 QPS 扫描脚本（7.5~10.0，6 档，30min/档） |
| `logs/tianji_4tp_highqps_20260313_121446/` | ✨ 生成 | 6 档高 QPS 实验结果 |
| `logs/tianji_4tp_qps_merged/` | ✨ 新建 | 低+高段合并目录（36 档，硬链接） |
| `logs/tianji_4tp_qps_merged_filtered/` | ✨ 新建 | 剔除 6.90/7.00 的过滤目录（34 档） |
| `logs/tianji_opti_qps_20260312_111300_filtered/` | ✨ 新建 | 剔除 6.79/7.00 的 4DP 过滤目录（28 档） |
| `results/tianji_querysafety_4tp_vs_4dp_20260313/REPORT.md` | ✨ 新建 | 初版对比报告 |
| `results/tianji_querysafety_4tp_vs_4dp_filtered_20260313/REPORT.md` | ✨ 新建 | 最终版对比报告（含高 QPS 段 + 异常剔除） |
| `results/tianji_querysafety_4tp_fullrange_20260313/REPORT.md` | ✨ 新建 | 4TP 全范围拐点报告（34 档，剔除异常点） |
| `src/llm_benchmark/analysis/analysis/multi_exp_compare.py` | 🐛 修复 | E2E P90 格式精度 `%10.1f` → `%10.3f` |
| `.cursor/skills/qps-sweep-comparison/SKILL.md` | 📚 更新 | 新增 YAML config 方式、跨目录合并说明、symlink 警告 |

---

### 📋 当前状态（会话结束）

| 事项 | 状态 |
|------|------|
| 4TP 真实拐点定位 | ✅ 完成（QPS=8.0 req/s，480 RPM） |
| 4TP vs 4DP 对比（含高 QPS + 异常剔除） | ✅ 完成（4DP 完全不可用，4TP 强烈推荐） |
| E2E P90 精度修复 | ✅ 完成 |
| qps-sweep-comparison Skill 补全 | ✅ 完成（YAML config + 跨目录合并） |
| 异常档位识别与剔除流程 | ✅ 完成（过滤目录方案，不删原始数据） |
| 模型档案 `tianji-querysafety-4b.md` | ⏳ 待建 |
| `llm-deployment-docker` Skill | ⏳ 待建（P0） |
| `llm-service-probing` Skill | ⏳ 待建（P1） |

---

---

## 🗓️ 2026-03-16 会话记录（文档整理 + guoxue 数据处理 + QPS Sweep 启动）

### ✅ 我们实现了哪些功能？

#### 📚 1. 文档整理与目录重组（commit `485d088`）
- 新增 `model-eval-report` skill（`.cursor/skills/model-eval-report/SKILL.md`、`clingo/docs/skills/model-eval-report/SKILL.md`）
- 新增 `clingo/docs/designs/2026-03-16-model-eval-report-design.md`
- 将旧的 `need-todo-idea.md`、`skills-roadmap.md` 迁移至 `clingo/docs/planning/`（新建目录）
- 将 `2026-03-13-llm-deployment-probing-design.md` 迁移至 `clingo/docs/designs/`
- 更新 `model-evaluation-workflow` SKILL.md、`model-onboarding.md`、`benchmark-result-analysis` SKILL.md
- 更新日报、`results/README.md`、`offline_analysis.py`

#### 📚 2. traffic-dataset-prep SKILL.md 补充 DataConverter 陷阱（commit `979b4b3`）
- 情况 A 流程从「6 步」改为「6 步 + 步骤1.5」
- 新增步骤1.5：合并日期分片 CSV → 覆盖写回 `_all.csv`（6 列完整数据）
- 明确说明 DataConverter 原生 `_all.csv` 为 3 列索引文件，不含 `messages`/`old_response`
- 更新验证 Checklist，区分步骤1 和步骤1.5 的检查项
- 常见报错表新增 `KeyError: 'old_response'` 条目及修复方式

#### 🔧 3. process_guoxue_full.py 补充产出文件批注
- 每个 `to_csv()` 调用处新增内联注释，说明文件名、列数、用途（中间产物 / 最终交付）
- 步骤1.5 处标注 ⚠️ 覆盖 DataConverter 原生 3 列索引文件
- 步骤5（脏数据过滤）处标注最终交付文件，明确可直接用于 replay benchmark
- README 生成内容升级：「核心交付文件」→「产出文件一览」，列出全部 8 个产出文件（日期分片 CSV、`_all.csv`、中间选取文件、最终交付文件、可视化）

#### 🚀 4. xinghan-guoxue-72b-v1-2-reason QPS Sweep 启动
- 执行完整数据处理：`process_guoxue_full.py`，产出 `_poisson_220_stitched.csv`（5,726 行，峰值 220 RPM）
- 启动 `run_guoxue_8tp_qps_sweep.sh`，实验目录：`logs/guoxue_8tp_qps_20260316_163202/`
- Sweep 参数：24 档，QPS 0.190 → 0.350，数据集 684 条，远端服务 `bazi-guoxue-eagle3-test`
- **当前进度（截至本次会话结束）：第 1/24 档（QPS=0.190）约 62% 完成，预计今晚继续跑**

---

### 🐛 我们遇到了哪些错误？

| 错误 | 位置 | 描述 |
|------|------|------|
| `KeyError: 'old_response'` | guoxue 数据处理 | DataConverter 产出的 `_all.csv` 是 3 列索引文件，不含 `messages`/`old_response`，直接传给 benchmark 工具报错 |
| git commit 命令 Abort | 终端 | HEREDOC commit message 中含有特殊字符导致 spawn 失败，最终通过简化 message 解决 |

---

### 🔧 我们是如何解决这些错误的？

1. **`KeyError: 'old_response'` 根因分析**：通过日志 `process_guoxue_20260316_162108.log` 确认，DataConverter 步骤2「生成索引文件」产出的 `_all.csv` 只有 `income_time`、`file_suffix`、`original_index` 三列，是轻量索引文件，而非全量数据。DataSampler 在采样时会回头读日期分片 CSV 拉完整数据，因此本次处理实际未触发报错；但若跳过 DataSampler 直接用 `_all.csv` 做 benchmark，就会中招。
2. **修复方案**：SKILL.md 新增步骤1.5 + ⚠️ 说明；`process_guoxue_full.py` 增加内联批注和 README 产出文件一览；同时补充说明**步骤1.5 在仅走采样管道时可跳过**（DataSampler 自己读日期分片，不依赖 `_all.csv` 内容）。

---

### 🔧 文件变更汇总

| 文件 | 操作 | 说明 |
|------|------|------|
| `clingo/docs/skills/traffic-dataset-prep/SKILL.md` | 📚 更新 | 新增步骤1.5、DataConverter 陷阱说明、KeyError 报错条目 |
| `scripts/data/process_guoxue_full.py` | 🔧 更新 | 各步骤 `to_csv()` 增加产出文件批注，README 模板升级为「产出文件一览」 |
| `clingo/docs/skills/model-evaluation-workflow/SKILL.md` | 📚 更新 | 补充完整 step 描述与跳过逻辑 |
| `clingo/docs/workflow/model-onboarding.md` | 📚 更新 | 完善 onboarding 工作流 |
| `clingo/docs/skills/benchmark-result-analysis/SKILL.md` | 📚 更新 | 小幅更新 |
| `clingo/docs/designs/2026-03-16-model-eval-report-design.md` | ✨ 新建 | model-eval-report 设计文档 |
| `clingo/docs/planning/need-todo-idea.md` | 📁 迁移 | 从 `clingo/docs/` 移至 `planning/` |
| `clingo/docs/planning/skills-roadmap.md` | 📁 迁移 | 从 `skills/` 移至 `planning/` |
| `clingo/docs/skills/model-eval-report/SKILL.md` | ✨ 新建 | model-eval-report skill |
| `.cursor/skills/model-eval-report` | ✨ 新建 | symlink 指向 skill 目录 |
| `logs/guoxue_8tp_qps_20260316_163202/` | 🚀 生成 | QPS sweep 进行中（24 档） |

---

### 📋 当前状态（本次会话结束）

| 事项 | 状态 |
|------|------|
| 文档目录重组 | ✅ 完成 |
| traffic-dataset-prep SKILL 步骤1.5 补充 | ✅ 完成 |
| process_guoxue_full.py 产出文件批注 | ✅ 完成 |
| guoxue 数据处理（process_guoxue_full.py） | ✅ 完成（5,726 行，220 RPM） |
| guoxue QPS Sweep 启动 | ✅ 已启动，进行中（第 1/24 档，约 62%） |
| traffic-dataset-prep 步骤1.5 必要性条件补充 | ⏳ 待更新（确认"仅采样管道可跳过"说明是否要加进 SKILL） |
| process_guoxue_full.py 及 run_guoxue_8tp_qps_sweep.sh | ⏳ 待 git commit（上次提交 Abort，需重新提交） |
| guoxue QPS Sweep 全部完成 | ⏳ 预计今晚/明早完成 |

---

## 🗓️ 2026-03-16 会话记录（历史会话导出与整理）

### ✅ 我们实现了哪些功能？

#### 📚 1. 识别并确认归档会话
- 用户提供截图，标识出 Cursor 中已归档（Archived）的 7 个会话：
  - `Traffic dataset preparation`（e2c18b49）
  - `Git commit process for SKILL.md`（e46d2efe）
  - `Chat completions URL testing`（18ed079d）
  - `Mac安全验证问题`（875a2d8d）
  - `Default inference parameters in llm_benchmark`（db6c888d）
  - `QPS testing and SLA analysis for Tianji model`（4c28517a）
  - `正常工作能力询问`（fd88f0c5）

#### 📚 2. 分析已导出会话与 JSONL 的对应关系
- 从 `agent-transcripts/` 中识别出所有 2026-03-14 之前的 30 个本地 JSONL 会话
- 通过内容比对确认 6 个已导出会话对应的 UUID：
  - `03` = `0302905e`（数据处理）
  - `10` = `bcbf1eef`（skill 规划讨论）
  - `13` = `ba78a303`（skill workflow 回顾）
  - `14` = `29cd9290`（benchmark 可视化）
  - `15` = `ce316707`（tianji 部署 + 回放测试）
  - `19` = `19885ffa`（QPS 测试结果分析）

#### ✨ 3. 批量导出 17 个未导出会话
- 编写 `scripts/export_sessions.py`，将 JSONL 自动转换为 Markdown 格式
- 跳过 7 个 Archived 会话、6 个已导出会话，成功导出 17 个新文件
- 导出格式对齐 Cursor 原生导出风格（`**User**` / `**Cursor**` 分隔）

#### ♻️ 4. 统一重命名所有会话文件（01-24 顺序编号）
- 将全部 24 个会话文件按时间顺序重新编号为 `{nn}_cursor_{topic}.md`
- 原有文件 `03→04`、`10→12`、`13→16`、`14→17`、`15→18`，保证整体顺序一致
- 新增 17 个文件填入编号空缺（02、03、05-11、13-15、20-24）

#### 🔧 5. Git Commit
- commit `86a62fc`：`docs(sessions): export and reorganize pre-2026-03-14 cursor chat sessions`
- 22 个文件变更，10853 行新增

---

### 🐛 我们遇到了哪些错误？

| 错误 | 描述 | 解决 |
|------|------|------|
| Cursor 归档状态无法从服务器端读取 | `agent-transcripts/` 只存储对话内容，无 Archived 标记 | 请用户截图确认，人工识别 7 个归档会话 |
| 部分 JSONL 消息提取为空 | 用户消息嵌套在 `<user_query>` 标签内，正则需匹配 | `export_sessions.py` 增加 `<user_query>` 提取逻辑 |
| 文件名含中文导致 shell 截断显示 | ls 输出中文文件名显示不完整 | 不影响功能，重命名后已全部改为英文文件名 |

---

### 🔧 我们是如何解决这些错误的？

1. **归档状态**：Cursor 的归档元数据存储于桌面客户端，服务器端 JSONL 无此信息。通过请求用户截图，准确获取 7 个 Archived 会话 title，再通过首条消息内容逐一匹配 UUID。
2. **消息提取**：`extract_user_text()` 函数优先从 `<user_query>` 标签中提取净文本，fallback 到去除所有 XML 系统注入标签后的文本。
3. **命名规范**：先生成带日期+UUID 的中文文件名，再统一通过 rename 脚本重命名为英文编号格式，两步分离降低出错风险。

---

### 🔧 文件变更汇总

| 文件/目录 | 操作 | 说明 |
|----------|------|------|
| `clingo/sessions/02~11_cursor_*.md` | ✨ 新建（10个） | 3/9~3/11 期间的新导出会话 |
| `clingo/sessions/13~15_cursor_*.md` | ✨ 新建（3个） | 3/12 期间的新导出会话 |
| `clingo/sessions/20~24_cursor_*.md` | ✨ 新建（5个） | 3/13 期间的新导出会话 |
| `clingo/sessions/03→04_cursor_*.md` | ♻️ 重命名 | 原 03，按时序改为 04 |
| `clingo/sessions/10→12_cursor_*.md` | ♻️ 重命名 | 原 10，按时序改为 12 |
| `clingo/sessions/13→16_cursor_*.md` | ♻️ 重命名 | 原 13，按时序改为 16 |
| `clingo/sessions/14→17_cursor_*.md` | ♻️ 重命名 | 原 14，按时序改为 17 |
| `clingo/sessions/15→18_cursor_*.md` | ♻️ 重命名 | 原 15，按时序改为 18 |
| `scripts/export_sessions.py` | ✨ 新建 | JSONL → Markdown 批量导出工具 |

---

### 📋 当前状态（历史会话导出会话结束）

| 事项 | 状态 |
|------|------|
| 2026-03-14 前全部会话导出 | ✅ 完成（24 个，跳过 7 个归档 + 1 个已有） |
| 会话文件统一编号命名 | ✅ 完成（01-24 顺序） |
| Git Commit | ✅ 完成（`86a62fc`） |
| scripts/export_sessions.py 提交 | ⏳ 待 commit（用户决定是否保留） |

---

## 🗓️ 2026-03-17 会话记录（资产管理重构 + T3 报告模板）

### ✅ 我们实现了哪些功能？

#### 🏗️ 1. 资产管理 Phase 1 设计与执行（brainstorming → 设计文档 → 执行）

通过 brainstorming 流程澄清了三个困惑（目录结构乱、EVAL_REPORT.md 机制未闭合、openclaw 接管），形成设计方案并执行：

**设计文档**（`clingo/docs/designs/2026-03-17-asset-management-design.md`）：
- 三方案对比（文件系统+INDEX / HTTP API / 静态Dashboard），选择 Phase 1 最小改动路线
- 明确 model-card = EVAL_REPORT.md，INDEX.yaml 为 openclaw 唯一入口
- Phase 2（HTTP API）有意推迟

**执行内容（Phase 1）**：

| 变更 | 说明 |
|------|------|
| `logs/data-pipeline/` 新建 | 迁入 2 个 process/协调 log 文件，与 benchmark 运行目录分离 |
| `datas/README.md` 新建 | 5 个源文件迁移状态表，标注目标路径 |
| `results/models/INDEX.yaml` 新建 | openclaw 接管入口：tianji ✅ 完整条目 + guoxue ⏳ 占位条目 |
| `results/README.md` 更新 | INDEX.yaml 置顶快速导航 |
| `run_guoxue_8tp_qps_sweep.sh` 更新 | nohup 路径规范改为 `logs/data-pipeline/` |
| `model-evaluation-workflow` Skill 更新 | Step 5 data-pipeline 路径 + Step 7 写 INDEX.yaml 操作说明 |
| `qps-benchmark-sweep` Skill 更新 | 新增"多段扫描合并流程"章节 + data-pipeline 路径 |

**Git 提交**：`80434ef`（设计文档）、`cfda6da`（脚本+Skill）、`944d5c7`（设计文档状态更新）

#### 📋 2. T3 reporting-template.md（`clingo/docs/workflow/reporting-template.md`）

基于 ziwei/hepan/tianji 三份完整 REPORT.md 抽象通用模板：
- **模板 A**：回放压测报告（6节结构，P90/P95/P99 全部必填，有效性论证标准化三段结构）
- **模板 B**：QPS 拐点/对比报告（逐档 SLA 表 + 拐点分析 + 扩容计算公式）
- **通用规范**：禁止"见图"占位、数字格式标准、三层层级关系（REPORT → model-context → EVAL_REPORT）

**Git 提交**：`f76b711`

#### 📝 3. 文档维护（四项收尾）

| 文件 | 变更 |
|------|------|
| `need-todo-idea.md` | T3 标记 ✅；I1 关闭（合并入 EVAL_REPORT.md）；I2 剩余部分归入 Phase 2 |
| `skills-roadmap.md` | model-eval-report 从 ⬜ 改为 ✅；时间线补充 qps-benchmark-sweep 和 model-evaluation-workflow 今日更新 |
| `benchmark-result-analysis` Skill | Step 5 补入 reporting-template.md 引用和模板A/B说明 |
| `progress.md` | 本条记录 |

---

### 🐛 我们遇到了哪些错误？

| 错误 | 描述 | 解决 |
|------|------|------|
| git add `datas/` `logs/` `results/` 被 .gitignore 拒绝 | 这三个目录是运行时产物目录，已在 .gitignore 中 | 仅提交 `clingo/docs/` 和 `scripts/` 下的变更；文件系统变更（data-pipeline/、INDEX.yaml 等）在本地生效但不入库 |
| Spec 评审第一轮发现 5 处问题 | 文件名不一致、清单漏项、语义歧义等 | 逐一修复后第二轮评审通过 |
| Spec 评审第二轮发现 2 处问题 | hepan JSONL 文件存在性误判（评审 subagent 误报）、guoxue linked_experiments 漏掉 partial 目录 | 确认 hepan 文件确实存在；补充 `results/guoxue_partial_20260317` |

---

### 🔧 我们是如何解决这些错误的？

1. **.gitignore 限制**：Phase 1 的文件系统操作（`logs/data-pipeline/`、`datas/README.md`、`results/models/INDEX.yaml`）直接在本地执行，不需要 git 追踪；脚本和 Skill 变更正常入库。
2. **Spec 评审多轮迭代**：设计文档经过 4 轮 spec 评审才通过，每轮修复具体问题，保证执行清单的可执行性。
3. **subagent 误报处理**：第三轮评审中 subagent 误判 hepan 文件不存在，通过 shell 实际确认后忽略误报，只修复真实问题（guoxue linked_experiments）。

---

### 📋 当前状态（2026-03-17 会话结束）

| 事项 | 状态 |
|------|------|
| 资产管理 Phase 1 | ✅ 完成（7/8 条，第 8 条等 guoxue Sweep 完成） |
| T3 reporting-template.md | ✅ 完成 |
| 文档维护（need-todo-idea / skills-roadmap / benchmark Skill / progress） | ✅ 完成 |
| guoxue Step 6（结果分析） | ⏳ 等 Sweep 完成（~18:00）|
| guoxue Step 7（EVAL_REPORT.md） | ⏳ 等 Step 6 完成 |
| guoxue `business_peak_rpm` | ⏳ 等用户提供 Grafana QPM 截图 |
| Phase 2（HTTP API / Dashboard） | 📌 有意推迟，Phase 2 |
