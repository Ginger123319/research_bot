---

description: "每天工作日报,精简一些，不要总是说写了多少行代码，产出了多少文档这种事情，按STAR法则来说，背景，目标  做什么事情？ 为什么做？ 结果怎么样。言简意赅"
alwaysApply: true
---

# 📋 格式规范
format:
  timestamp: "ISO 8601 格式 (YYYY-MM-DD )"
  useEmojis: true
  codeHighlight: true
  linkToFiles: true
  linkToCommits: true

---

# 📅 2026-03-10 工作日报

## 一、模型服务探测与远端连通性验证

**背景**：新部署了两个 ziwei 系列模型服务，功能定位不明，需要确认各自角色并验证 k8s 平台远端服务可正常调用。

**做了什么**：对两个服务做了系统性功能探测（意图分类 vs 对话响应），并通过测试脚本验证了远端 URL 的连通性和推理正确性。

**结果**：
- 明确了架构：`8b`（:5291）作路由层（意图分类，~0.2s），`32b`（:5290）作响应层（~1s），"twostep" 即指此两步管道。
- 远端服务 5/5 全通，8b 意图分类准确率 100%，32b 响应正常，健康检查空 body 问题已修复。

---

## 二、压测数据准备——峰值流量数据集构建

**背景**：需要用真实线上流量对迁移后的 `xinghan-ziwei-32b-v1` 做压力验证，原始 JSONL 数据有格式问题（多天数据，时间戳不连续，峰值仅 16 RPM，低于 Grafana 监控峰值 29/100 RPM）。

**做了什么**：
1. 从原始 14,185 条 JSONL 中提取三天峰值窗口（各约 20 分钟），完整下载 COS prompt 内容填充 messages 字段。
2. 将三段时间戳不连续的峰值数据做首尾拼接（压缩为连续 60 分钟），消除段间 ~23.5 小时的大间隔（直接回放会让 benchmark 等待 23 小时）。
3. 通过泊松插值将流量从 486 条放大至 3,036 条，峰值达到 100 RPM。
4. 过滤掉 3 条 `content` 为 list 的多模态格式数据（会导致 Jinja 模板报 `TypeError`）。

**结果**：生成可直接用于 `--keep-income-time` 回放的压测数据集（3,036 条，峰值 100 RPM，messages 全部有内容）。

---

## 三、100 RPM 峰值回放压测 & 迁移验证报告

**背景**：数据集就绪后，需要执行正式压测并出具报告，佐证新部署服务可承接线上峰值流量。

**做了什么**：按真实时刻时序回放 3,036 条请求（`--keep-income-time`，峰值 100 RPM），压测约 60 分钟，随后深度解析结果并与 Grafana 历史监控横向对比，撰写完整迁移验证报告。

**结果**：

| 指标 | 值 |
|------|----|
| 成功率 | **99.97%**（3035/3036） |
| TTFT P90 | 1.002s |
| E2E P90 | 7.476s |
| 综合吞吐 | 3,536 tokens/s |

- 压力为早期测试 **3.5×**，延迟仅小幅上升，无雪崩。
- 各项指标优于或持平 Grafana 线上历史数据，服务具备上线条件。
- 产出 [`REPORT.md`](../../results/ziwei_benchmark_20260310_163524/REPORT.md)（含 6 章结构、8 张分析图、有效性论证）。

---

## 四、QPS 拐点压测脚本设计（为后续扫描备用）

**背景**：需要找到 8TP / 4TP 单实例部署下的 QPS 性能拐点，以支撑容量规划决策。4TP 历史已跑但有数据集路径错误导致多档失败，中间大量档位空缺。

**做了什么**：设计并编写了两套扫描脚本——8TP 从 1.00→0.46 共 20 档（高负载区 0.02 步进细粒度），4TP 补全 16 个缺失档位，两套脚本数据集统一换为全量 12,789 条，结构对齐。

**结果**：脚本就绪，可随时一键启动；预估 8TP 约 18 小时、4TP 约 14 小时完成全程扫描。

---

# 📅 2026-03-12 工作日报

## 一、sglang 镜像迁移 & ziwei 双服务 k8s 部署验证

**背景**：ziwei 32b + 8b 两个服务需要迁移到新平台，依赖的 sglang 镜像分散在不同 registry，需要统一命名空间后才能在 k8s 上拉取。

**做了什么**：将两个 sglang 镜像（v0.4.1.post4 / v0.4.6.post2）打 tag 推送至 `reg.xxwolo.com/master/`；编写验证脚本对新部署的两个服务（32b 通用推理 + 8b 意图识别）做功能测试，覆盖 health、models 接口和各自专项能力。

**结果**：镜像推送成功（推送权限问题自行解决）；32b 和 8b 服务功能测试全绿，响应速度符合预期（8b ~0.2s，32b ~1~4s）。

---

## 二、hepan-72b 峰值回放结果离线分析 & 图表 Bug 修复

**背景**：同事已跑完 hepan-72b 回放压测，需要产出标准化分析报告；同时发现分析工具的 Token Length Distribution 图表存在视觉异常——所有数据都挤在最左侧第一个 bin，实际分布完全看不出来。

**做了什么**：对 6,034 条压测结果做离线分析，产出 HTML + PNG + REPORT.md；排查图表压缩问题，根因是全局 `tok_max` 导致 bin 过宽，修复为每个系列独立用 P99 作为 x_max，同时将 Token/Latency 直方图统一应用该逻辑。

**结果**：
- hepan-72b 回放成功率 **99.95%**，TTFT P90 = 1.147s，E2E P90 = 13.379s，Prefill 吞吐 3,624 tokens/s
- 图表修复验证通过，`first_sentence` 系列分布清晰可见（峰值在 ~13 token 区间）

---

## 三、hepan QPS 扫描多组对比 & ziwei TP8 vs TP4 完整报告

**背景**：同事提供了两组不同数据集下的 QPS 扫描结果（orig / data600），需要对比两组 SLA 拐点是否一致；同时 ziwei TP8 vs TP4 的分析分散在 logs 目录，需要整合成一份正式报告。

**做了什么**：在 `multi_exp_compare.py` 中新增 `file_pattern` 过滤参数，解决同一目录下多组文件混杂无法单独筛选的问题；完成 hepan 双组对比分析和 ziwei 双配置完整重跑分析。

**结果**：
- hepan orig vs data600：SLA 拐点均为 **0.80 req/s（48 RPM）**，data600 TTFS P90 低约 3~4%，结论一致——服务侧算力是瓶颈而非数据集差异
- ziwei TP8 vs TP4（SLA: TTFS P90 ≤ 1.5s）：TP8 拐点 **1.50 req/s**，TP4 拐点 **0.92 req/s**，TP8 承载约 TP4 的 **1.63×**

---

## 四、tianji-querysafety 回放基准测试 & Skill 体系收尾

**背景**：tianji-querysafety 模型完成部署后，需要执行回放压测验证服务性能，并与 Grafana 线上历史监控对比佐证有效性；同时 llm-replay-benchmark Skill 需要通过真实用例确认。

**做了什么**：对 44,099 条真实线上请求按原始时刻时序回放（`--keep-income-time`），生成完整分析报告；将 Grafana 截图中的历史指标与压测数据逐项对比写入 REPORT.md；更新 Skill 路线图和 need-todo 完成状态。

**结果**：

| 指标 | 值 |
|------|----|
| 成功率 | **100.00%** ✅ |
| E2E 均值 | 0.214s（与 Grafana 线上 0.175~0.225s 完全吻合）|
| Prefill 吞吐 | 119,884 tokens/s |
| 峰值覆盖 | 回放均值 1469 RPM，充分覆盖 Grafana 历史峰值 ~2000 RPM/分钟 |

- `llm-replay-benchmark` Skill 通过 ziwei-32b + tianji-querysafety-4b 两模型实测验证，状态更新为 ✅ 已验证
- `benchmark-result-analysis` Skill 通过三模型验证闭环（ziwei + hepan + tianji）

---

# 📅 2026-03-13 工作日报（摘要见上）

---

# 📅 2026-03-16 工作日报

## 一、tianji-querysafety 4TP QPS 拐点完整定位

**背景**：昨天启动的初段扫描（4.0→7.0 QPS，30 档）全部 PASS，说明测试范围不足，需补测高 QPS 段找到真实拐点；同时发现 QPS=6.9/7.0 出现 E2E 骤降异常，需要定性解释。

**做了什么**：
1. 补测高 QPS 段（7.5→10.0，6 档，30min/档），将低段 + 高段合并为 36 档全量数据。
2. 精确计算 30 档原始 token_list 时间戳，提取 E2E P50/P90/P95/P99，将分析精度从 1 位小数提升至毫秒级。
3. 剔除 KV Cache 热身骤降的异常点（QPS=6.90/7.00），以 34 档干净数据定位拐点。
4. 将缓存现象升级为三阶段机制解释——Q<6.59 缓存不稳定→P99 波动；QPS=6.90 请求密度达阈值→8K prefix 锁定热区；QPS=7.00 发生质变→TTFT 减半（前缀 prefill 几乎 100% 跳过）。

**结果**：拐点定位为 **QPS ≈ 8.0~8.5 req/s（480 RPM）**，E2E P95 在 8.5 时首次超标（0.422s）；当前业务峰值 2168 RPM 需 **6 实例 × 4TP** 承载（含 20% 余量）。

---

## 二、4TP × 1 vs 1TP × 4DP 部署方式对比

**背景**：昨天新部署了 1TP×4DP 服务，需要与 4TP×1 实例做 SLA 对比，确认哪种部署方式更适合该模型。

**做了什么**：用 `multi_exp_compare.py` 对两组实验（4TP 34档 / 4DP 28档，均剔除异常点）做双组对比分析；对异常档位采用"建过滤目录+硬链接"方案，保留原始数据完整性。

**结果**：4DP 全部 30 档 FAIL，E2E P90 在 1.5~2.5s，超出 400ms 门限 **4~8 倍**，完全不适用；4TP 全部 PASS，结论清晰——**当前场景强烈推荐 4TP 部署**。

> 附注：`ln -sfn` 符号链接目录会导致 `Path.glob("**/*.csv")` 无法遍历（Python 默认不追踪目录软链接），需用 `cp -rl` 硬链接替代，已记入 Skill。

---

## 三、分析工具链改造

**背景**：每次分析都需要修改脚本底部配置，不便于复用；E2E P90 格式精度只有 1 位小数（如 0.138s 显示为"0.1"），细节全部丢失，导致误判。

**做了什么**：为 `multi_exp_compare.py` 新增 `--config` / `-c` 参数，支持外部 YAML 驱动（`configs/` 目录下新建 template + 2 个示例配置）；修复 E2E P90 格式串 `%10.1f` → `%10.3f`，新增 E2E P95/P99 列。

**结果**：工具改造完成并验证运行；精度修复后 P95 软拐点特征（P90 PASS 但 P95 超标）可被准确捕捉，不再被粗粒度掩盖。

---

## 四、`model-evaluation-workflow` 顶层编排 Skill 完成（T8）

**背景**：Skill 路线图中最后一个待建项——新模型接入全流程编排 Skill，需要将已有的 7 个原子 Skill 串联为可复用的工作流。

**做了什么**：设计并编写 `model-evaluation-workflow` Skill（两阶段 + 人工断点结构：本地准备 → 等待 k8s endpoint → 远端评估），涵盖 Step 0~6 的跳过条件（支持跨会话续跑），处理形态 A（命令行方式）和形态 B（Dockerfile 方式）两种部署信息来源。

**结果**：8 个 Skill 全部完成，Skill 路线图清零；同步更新了 need-todo-idea（T8 打勾）和 clingo/docs/README（体系表 7→8）。

---

## 五、HTTP 文件服务器优化

**背景**：用浏览器查看 REPORT.md 时中文全部乱码；服务器无外网访问，无法使用 CDN 加载 Markdown 渲染库。

**做了什么**：新建 `scripts/serve.py`，继承 `SimpleHTTPRequestHandler`，强制为文本文件注入 `charset=utf-8`；采用服务端渲染方案（`markdown-it-py`，服务器已安装），CSS 全部内联，完全离线，支持 GFM 表格、代码块、图片；用 `nohup` 启动脱离 shell 会话。

**结果**：两个服务（results/:18999 / logs/:8765）均可正常渲染 Markdown，中文不再乱码，图片相对路径自动可用，`?raw=1` 支持查看原始文本。

---

# 📅 2026-03-11 工作日报

## 一、ziwei QPS 拐点扫描范围扩展

**背景**：昨天低QPS扫描（1.0→0.46）完成后，发现 QPS=1.0 时服务远未达边界，需要向高QPS方向继续探索；同时 4TP 在 QPS=1.0 时结果异常，需重跑。

**做了什么**：为 8TP / 4TP 各新建一套高QPS探索脚本（2.0→1.1 / 2.0→1.0），保留原脚本不动，同步给所有脚本的子目录加 `TP8_` / `TP4_` 前缀以区分；每档时长从 60min 压缩至 30min 避免过载档位阻塞过久。

**结果**：4 套脚本形成完整覆盖矩阵（低QPS细粒度 + 高QPS均等探索），两个高QPS探索脚本已并行启动（8TP ~5.5h / 4TP ~6h）。

---

## 二、4TP 三批历史结果合并整理

**背景**：`run_ziwei_4tp_qps_benchmark.sh` 执行产出了 3 个目录（格式不一：平铺 vs 子目录），无法直接用 analysis 工具统一分析。

**做了什么**：编写合并脚本，将三批目录（含平铺格式和子目录格式）统一复制为 `TP4_qps_X.XX/` 子目录格式，原始目录保持完整不动。

**结果**：生成 `logs/ziwei_4tp_qps_20260310_all/`，共 24 档（0.46~1.00），目录格式统一，可直接交给 analysis 工具批量分析。

---

## 三、tianji-querysafety-4b-v2-3 新模型部署与验证

**背景**：`tianji-querysafety-4b-v2-3` 是新接入模型，需完成本地部署验证并明确其功能定位（是分类器还是拦截式对话助手）。

**做了什么**：编写容器启动脚本完成本地部署；设计并迭代两版探测脚本（v1→v2，新增 `expect_reject` 自动判定、拦截准确率统计、延迟分位数基准）；执行 GPU 拓扑分析评估 TP 策略合理性。

**结果**：
- 明确模型定位：拦截式安全助手——违规请求 ~0.1~0.3s 快速拒绝，安全请求 ~1.4s 正常回答，而非返回分类标签。
- 建议从 `TP=4` 改为 `TP=1×DP=4`（PCIe L20 机器无 NVLink，AllReduce 通信为瓶颈）。
- 本地及 k8s 平台部署均已验证可用。

---

## 四、hepan 合盘数据处理 & data_analysis CLI 修复

**背景**：复现同事的数据处理结果时，只得到 18,567 条（31%），同事得到 58,871 条，差距显著，根因不明。

**做了什么**：
1. 排查发现同一模型在 JSONL 中有两种写法（英文 ID + 中文别名），CLI `-m` 只能传单个别名是根本缺陷。
2. 修复 `data_analysis` CLI 的 `menu.py`，支持逗号分隔多别名（`-m "xinghan-hepan-72b-v1-2,星盘合盘"`）。
3. 基于全量 58,871 条数据重新分析峰值（74 RPM，远高于之前基于不完整数据估算的 30 RPM），更新处理参数，重跑完整 5 步管道。
4. 提交 `wnd_dev` 分支（commit `33e32bf`），并为三个核心模块补写 API 参考文档。

**结果**：hepan 全量转换与同事 0 差值；最终压测数据集 6,034 条（150 RPM）；CLI 修复已提交，待 push 后提 MR。

---

## 五、项目工程化建设（Skill 体系 + 目录重组 + SOP + tianji 压测启动）

**背景**：随着接入模型增多，重复劳动多、经验未沉淀，需要系统化固化工作流。

**做了什么**：
- 建立 `clingo/docs/` 文档体系（项目概览、需求待办、Skill 路线图）。
- 将 `tmp/` 下 15 个脚本按功能分类迁移到 `scripts/{deploy,benchmark,probe,data,analysis}/`。
- 创建 `traffic-dataset-prep` Skill（含情况 A JSONL / 情况 B CSV+模板 双路径，覆盖 ziwei + hepan + tianji 三个模型实测验证）。
- 编写 `model-onboarding.md` SOP（6 步完整评估流程 + Checklist）。
- 完成 tianji-querysafety 数据处理（281,435 条全量 → 44,099 条峰值数据，修复 `prompt` 列缺失导致的 `KeyError`），启动 QPS 扫描任务（7.0→4.0，30 档，预计 ~23h）。

**结果**：项目文档/脚本/Skill 三套体系初步建立；tianji QPS 扫描正在执行中。

---

# 📅 2026-03-16 工作日报

## 一、文档体系整理与目录重组

**背景**：随着 Skill 数量增多、文档散落在多个层级，`clingo/docs/` 目录结构混乱，规划类文档（need-todo、skills-roadmap）与 Skill 文件混放，不便于维护。

**做了什么**：新建 `clingo/docs/planning/` 目录，将 `need-todo-idea.md` 和 `skills-roadmap.md` 从原来的位置迁移进去；新增 `clingo/docs/designs/` 存放设计文档；同步更新 `model-evaluation-workflow`、`model-onboarding.md`、`benchmark-result-analysis` 等相关文档；新增 `model-eval-report` Skill 及其设计文档。两次变更分别提交（commit `485d088`、`979b4b3`）。

**结果**：目录职责清晰（skills/ 只放 Skill、planning/ 放规划、designs/ 放设计），后续维护更顺畅。

---

## 二、traffic-dataset-prep Skill 补充 DataConverter 陷阱

**背景**：处理 guoxue 数据时发现 DataConverter 产出的 `_all.csv` 是 3 列轻量索引文件（非全量数据），若跳过 DataSampler 直接拿去跑 benchmark 会触发 `KeyError: 'old_response'`，这个陷阱之前的 Skill 中没有记录。

**做了什么**：在情况 A 流程中插入「步骤1.5：合并日期分片 CSV → 覆盖写回 `_all.csv`（6 列完整数据）」，明确说明 DataConverter 原生 `_all.csv` 不含 `messages`/`old_response`；常见报错表补录 `KeyError: 'old_response'` 条目；同步更新 `process_guoxue_full.py` 各步骤的产出文件内联批注和 README 模板。

**结果**：Skill 陷阱说明完整，后续新模型接入可避免踩同一个坑。

---

## 三、guoxue 数据处理 & QPS Sweep 启动

**背景**：`xinghan-guoxue-72b-v1-2-reason` 模型需要做 QPS 拐点评估，数据处理和压测脚本均需要从头准备。

**做了什么**：执行完整数据处理管道（`process_guoxue_full.py`），产出 `_poisson_220_stitched.csv`（5,726 行，峰值 220 RPM）；编写并启动 `run_guoxue_8tp_qps_sweep.sh`（24 档，QPS 0.190→0.350，远端服务 `bazi-guoxue-eagle3-test`）。

**结果**：压测任务已后台启动，第 1/24 档进行中，预计今晚跑完。

---

## 四、历史会话批量导出与整理

**背景**：2026-03-14 前的 30 个 Cursor 对话只有部分做了手动导出，大量会话内容散落在 agent-transcripts JSONL 中，需要统一归档为可读 Markdown。

**做了什么**：编写 `scripts/export_sessions.py`，将 JSONL 自动转换为对齐 Cursor 原生导出风格的 Markdown；识别并跳过 7 个已归档会话（通过用户截图人工比对），成功导出 17 个新文件；将全部 24 个会话文件统一按时间顺序重命名为 `{nn}_cursor_{topic}.md`，提交 commit `86a62fc`（22 文件，10853 行新增）。

**结果**：2026-03-14 前所有会话全部归档入 `clingo/sessions/`，编号连续（01-24），历史可追溯。

---

# 📅 2026-03-17 工作日报

## 一、资产管理体系 Phase 1 落地

**背景**：随着评估模型增多，实验结果散落在 `logs/`、`results/`、`datas/` 等多处，没有统一的结构化入口，模型档案机制（EVAL_REPORT.md）也未闭合，需要建立可被后续工具（openclaw）接管的最小资产管理体系。

**做了什么**：通过 brainstorming → 设计文档 → Spec 评审（4轮）→ 执行的完整流程，落地 Phase 1：新建 `results/models/INDEX.yaml` 作为模型统一入口，建立 `logs/data-pipeline/` 区分流水线日志与实验结果，编写 `clingo/docs/workflow/reporting-template.md`（模板 A 回放报告 / 模板 B QPS 拐点报告），同步更新相关 Skill（`model-evaluation-workflow`、`qps-benchmark-sweep`）。

**结果**：Phase 1 核心结构就位，commit `485d088`、`cfda6da`、`f76b711`；Phase 2（HTTP API / Dashboard 数据层）有意推迟。

---

## 二、Dashboard Phase 1 全面完成

**背景**：INDEX.yaml 建立后，需要一个可视化界面展示各模型评估状态，供内部快速查阅，完全离线、不依赖外部服务。

**做了什么**：扩展 `scripts/serve.py`，新增卡片式 Dashboard（`/`）和 JSON API（`/api/models`），显示部署配置、拐点数据、推荐建议、实验链接；修复 5 个验收问题（localhost 链接改用真实 IP、in_progress 占位文本、insights 区块位置、错误页友好提示等）。

**结果**：18 项验收全部通过，commit `b620298`、`5449d08`；Dashboard 实时反映 INDEX.yaml 中的最新数据，数据更新时间戳可见。

---

## 三、ziwei + hepan 模型档案补全

**背景**：两个最早完成评估的模型（ziwei-32b、hepan-72b）缺少标准化的 `model-context.md` 和 `EVAL_REPORT.md`，无法在 Dashboard 中正常展示，也无法被 openclaw 接管。

**做了什么**：为两个模型各创建 `model-context.md` 和 `EVAL_REPORT.md`，写入部署规格、SLA 拐点、扩容建议；修复 `hepan_benchmark_20260312/REPORT.md` 中遗留的 `<见图>` 占位符（补入 TTFS/ITL 真实百分位数值）；更新 INDEX.yaml。

**结果**：ziwei（TP8×2=16卡推荐 vs TP4×3=12卡备选）、hepan（5实例×8TP=40卡 L20）档案完整，Dashboard 显示正常。

---

## 四、guoxue QPS Sweep 分析 & 文档交付

**背景**：昨天启动的 guoxue 24 档 QPS Sweep（~25 小时）今日完成，需要完成 Step 6 分析、Step 7 文档，并将模型注册到 INDEX.yaml。

**做了什么**：用 `multi_exp_compare.py` 并行分析全部 24 档；对比两张 Grafana 截图（裸模型 43 RPM vs 上游 MCP 213 RPM）确认真实业务峰值；生成完整 REPORT.md、model-context.md、EVAL_REPORT.md，INDEX.yaml 将 guoxue 从 `in_progress` 更新为 `completed`。

**结果**：guoxue 拐点定位在 QPS=0.245 req/s，软拐点特征（E2E 平稳增长，TTFS 全程 ≤ 0.86s 远低于门限）；因缺少回放测试，上线结论标注为 ⚠️ 待补充，不提前下结论。**5 个模型全部 completed，Dashboard 清零进行中。**

---

## 五、lingyu 模型资产补全（协作整理）

**背景**：同事已完成 lingyu-235b-A22b-v9-2 的 QPS Sweep 并生成了部分结果，但 `model-context.md` 有 7 处 null 字段、INDEX.yaml 缺少该模型、原始 CSV 数据分散在共享目录，需要统一整理入库。

**做了什么**：将 60 个原始 CSV 从共享工作区迁移至 `logs/lingyu_qps_sweep_20260317/`；从原始 CSV 解析 `token_list` 时间戳计算真实 TTFT/E2E P90（修正了以 `income_time` 为基准导致的荒谬数值 bug）；补全 model-context 全部字段；创建 EVAL_REPORT.md（21 档 SLA 明细表）；在 INDEX.yaml 注册完整条目；修复 Dashboard 链接端口错误（`logs/` 路径应路由 8765 端口，改为 `results/` 走 18999 端口）。

**结果**：lingyu 档案完整，Dashboard 警告消除，6 个模型档案全部可正常展示。

---

# 📅 2026-03-18 工作日报

## 一、chart 模型数据处理（解决 JSONL 索引文件问题）

**背景**：`xinghan-chart-32b-v1-1-agent` 是新接入模型，历史处理脚本全部失败（得 0 条数据），原因不明，需从头排查并获取可用压测数据集。

**做了什么**：逐层调研 chart JSONL 格式，发现与 guoxue/ziwei 的根本差异——chart 的 `messages` 字段是 COS URL 字符串而非内联 list，DataConverter 的 `isinstance(msgs, list)` 判断直接失败；参考 SpecForge 的 `download_by_indices.py` 方案，通过 `raw_content` URL 两层下载获取真实数据（47,338 条全量，耗时 ~41 分钟，100% 成功）；转换后发现 41K 条走 Agent 框架的记录 prompt 为空（动态计算，无法还原），最终可用 6,016 条直接调用记录；调整每档时长 2700s→1500s 以匹配数据集规模，启动 8TP 和 4TP 双组 QPS Sweep。

**结果**：6,016 行 benchmark 数据集就绪，8TP/4TP 两组压测任务后台并行运行，预计明早出结果。

---

## 二、TTFS 指标计算错误修复 & 多 CSV 对比工具

**背景**：同事反馈某次 benchmark 结果中 TTFS 与 TTFT 数值完全相同，怀疑计算有误。

**做了什么**：定位到两个叠加错误——语义错误（TTFS 被误解为"首字节"而非"首句"）+ 计算错误（ad-hoc 脚本跳过 `analysis_response()`，直接用 TTFT 值填充 TTFS）；新建 `scripts/analysis/compare_analysis.py`，通过正确路径解析 `token_list` 计算真实 TTFS（扫描中文标点定位首句边界），支持多 CSV 横向对比并输出含变化百分比的 Markdown 表格；在 `benchmark-result-analysis` Skill 中补充"⚠️ TTFS 常见误解"警告表和多 CSV 对比章节，commit `8ac0917`。

**结果**：用正确脚本重算后，TTFS P90 从错误的 0.525s 修正为 1.255s（+0.730s）；还发现被掩盖的问题——0.5.5 版本 TTFS P90 实际劣化了 +21.1%，而非旧结果显示的 +6.8%。

---

## 三、qps-peak-finder 新方法在 guoxue 模型上实践验证

**背景**：传统网格扫描找 QPS 拐点需要 20+ 档、约 25 小时，效率太低；新的 qps-peak-finder 方法（饱和探测 + 自适应逼近）理论上可大幅缩短，需要在真实模型上验证。

**做了什么**：Phase 1 通过并发翻倍步进找到 guoxue 模型的峰值吞吐（con=120 时 716.9 tokens/s，极限 RPS=0.371）；Phase 2a 基于比例步进自动逼近 SLA 合规点，循环执行 4 档后逼近至 rps=0.2529 进行中；过程中修复了三处脚本 bug（`worst_ratio` 初始化错误导致假收敛、`KeyError: raw_response`、孤立 elif 语法错误）；将核心分析脚本迁移至 `scripts/analysis/analyze_peak_finder.py`，新建 `run_phase1_saturation.sh` 和 `run_phase2_auto.sh` 执行脚本。

**结果**：Phase 1 完成，极限 RPS 已确定；Phase 2a 收敛中，预计再 1~2 档可定位 SLA 合规拐点；方法可行性验证通过。

---

## 四、通用 Benchmark Runner 框架设计与实现

**背景**：随着模型数量增加，每个模型都有一套专属脚本（run_chart_8tp_qps_sweep.sh、run_guoxue_8tp_qps_sweep.sh…），维护成本高，逻辑重复，新模型接入需要大量复制改写。

**做了什么**：设计并实现"通用脚本 + `.env` 配置文件"体系（方案 C）：三个通用脚本（`run_qps_sweep.sh`、`run_replay.sh`、`process.py`）接受 `.env` 路径参数，按 `DATA_FORMAT` 等字段自动分派逻辑；以 chart 模型为首个示例，创建 `configs/models/xinghan-chart-32b-v1-1-agent/` 下 8tp/4tp 两套 `.env` 及特例说明；同步更新 4 个 Skill（`qps-benchmark-sweep`、`llm-replay-benchmark`、`traffic-dataset-prep`、`model-evaluation-workflow`）新增"新模式执行方式"节。

**结果**：框架落地，新模型接入只需创建一个 `.env` 文件，无需再写专属 bash 脚本；4 个 Skill 均已同步，新成员可直接按 Skill 指引接入。

---

# 📅 2026-03-19 工作日报

## 一、chart-32b 空响应问题深度排查

**背景**：chart-32b 8TP/4TP QPS 扫描结果显示全部 SLA FAIL，初步诊断（nanobot）认为是 CSV 格式不兼容，需要复核真实原因。

**做了什么**：直接运行 `load_exp_csv()` + `analysis_response()` 复核，证明格式解析完全正常，推翻错误诊断；逐行检查发现真实根因是模型对 ~1% 请求返回空响应（`token_list` 仅 `[START]+[DONE]`，HTTP 200，首个 token 命中 `<|im_end|>` 对话结束符）；逐一排查并推翻四个假设（输入污染、特定 prompt 决定论、服务过载、短问题触发）；提取全量 20 档共 1,116 条空响应，建立完整事件报告。

**结果**：空响应是模型推理层的概率性问题，与压测 QPS 无因果关系；事件报告记录完整排查链路，为后续模型侧 fix 提供依据。

---

## 二、qps-peak-finder Skill 算法成熟化

**背景**：guoxue 模型 Phase 2 探测了 11 档仍振荡，核心问题是比例步进没有"历史记忆"，已知 bracket 区间 [0.2494 ✅, 0.2529 ❌]（宽 1.4%）本可 1 次收敛。

**做了什么**：在 `analyze_peak_finder.py` 新增 `--bracket-lo/hi` 参数，实现两阶段收敛——bracket 宽 ≥3% 时用几何中点（快速逼近），<3% 直接收敛；输出机器可读标记（`[SLA_PASS]`、`[SLA_FAIL]`、`[NEXT_RPS=X]`）；`run_phase2_auto.sh` 配套改造，每轮自动解析标记并更新 bracket；新增 `--phase 3` 汇总分析，更新 SKILL.md 中 Phase 3 定位描述（为容量曲线补充中间数据密度，而非再次逼近边界）。

**结果**：实测 guoxue bracket [0.2494, 0.2529] → 1 次即确认收敛（原需 11+ 次）；guoxue Phase 3 全部 SLA ✅，实验完整收尾。

---

## 三、guoxue 实验全量整理 & 报告交付

**背景**：qps-peak-finder 三阶段（Phase 1 饱和探测 / Phase 2 自适应逼近 / Phase 3 验证网格）全部完成，需要整理成标准化报告并更新模型档案。

**做了什么**：将 Phase 2+3 共 16 档用硬链接合并，跑 `qps-sweep-comparison` 生成 3 个容量曲线 HTML；生成完整 REPORT.md（含三阶段数据、与原网格搜索对比：时间节省 2/3，精度提升 5×）；更新 `model-context.md`（追加 peak-finder 系列字段）和 `EVAL_REPORT.md`（综合两轮实验，上线建议 ⚠️ 有条件上线，推荐 4 实例 × 8TP = 32 卡 L20）；修正实验目录位置（从 `results/models/<model>/` 移至 `results/` 根层）。

**结果**：guoxue 模型档案完整闭环，SLA 最大 QPS 0.2494 req/s 与原网格搜索 0.245 偏差仅 1.8%，交叉验证一致。

---

## 四、Dashboard 新增极限场景（Phase 1 饱和测试）指标展示

**背景**：Phase 1 饱和测试产出了极限 RPS 和可容并发数，这是容量规划和服务启动配置的重要参考，但 Dashboard 当前只展示 SLA 合规拐点，缺少硬件上限数据。

**做了什么**：在 INDEX.yaml 新增 `saturation_rps/rpm/concurrency` 三个可选字段；扩展 `serve.py`，新增 `.saturation-block` CSS 样式（浅黄背景 + 橙色边框，与 SLA 区视觉区分）和可折叠 `<details>` 渲染分支（无数据时静默跳过，零 JS 依赖）；归档设计文档。

**结果**：guoxue 卡片新增极限场景折叠区块（极限 RPS 0.371 / 可容并发 120），其他模型卡片无影响；全部验收项通过。

---

## 五、chart-32b QPS Peak Finder Phase 2 收敛 & Phase 3 启动

**背景**：chart-32b 8TP/4TP 两路 Phase 2 自适应逼近并行运行，发现 `run_phase2_auto.sh` 存在两个 bug 导致探测结果不可信，需修复并恢复正确收敛。

**做了什么**：定位并修复两个 bug——①bracket 更新后未重算几何中点（导致下一档比通过档还低）；②旧代码直接读 `CONVERGED` 标记未校验 bracket 宽度（导致 4TP 在 bracket 宽 50% 时误判收敛）；修复后 8TP 完成收敛（ideal_rps=7.6132 req/s，7 档），4TP 从误判点续跑（`INIT_LO/INIT_HI` 环境变量，bracket 当前 [4.192, 4.410]，还需 2 档）；8TP Phase 3（4 档 × 45min）已启动，4TP Phase 3 自动衔接脚本（每 30s 轮询日志）已就位待触发；在 SKILL.md 补充 `⚠️ 实现陷阱：next_rps 必须在 bracket 更新后重新计算` 详细说明。

**结果**：8TP Phase 2 收敛完成，Phase 3 运行中；4TP Phase 2 续跑中，Phase 3 将自动衔接；两个脚本 bug 均已修复并落入 SKILL 文档，防止复现。

---

# 📅 2026-03-20 工作日报

## 一、ziwei-32b 8TP Peak Finder 结果归档 & 生产风险预警

**背景**：ziwei-32b-v1 8TP Peak Finder 三阶段跑完，需要整理归档，并与实际生产负载（100 RPM）对比，确认当前容量是否充足。

**做了什么**：合并 Phase 2+3 共 10 档数据跑 `qps-sweep-comparison`，生成完整 REPORT.md，追加 model-context 和 INDEX.yaml 中的 peak-finder 字段；同时修复 Phase 1 自动脚本中 `MAX_RPS` 正则误提取 decode_throughput 值（`max_rps_estimate = 184.488 / 228.7 = 0.8065` 首次命中 184.488 而非最终结果）的 bug。

**结果**：ideal_rps = **1.5902 req/s（95.4 RPM）**；⚠️ **关键风险**：生产 100 RPM > SLA 上限 95.4 RPM，rps=1.6748 时 TTFS P90 = 1783ms（超限 19%），INDEX.yaml recommendation 已标注风险，需扩容。

---

## 二、chart-32b 回放测试结果分析 & EVAL_REPORT 交付（全流程闭环）

**背景**：chart-32b 峰值回放测试已在后台运行完成（110 分钟），需要完成 Step 6 结果分析和 Step 7 评估报告生成，完成该模型全流程闭环。

**做了什么**：分析 5,826 条回放结果，生成 HTML + 7 张 PNG 图表 + 详细 REPORT.md；调用 `model-eval-report` Skill 生成 EVAL_REPORT.md，计算资源建议（业务峰值 118 RPM，单实例 ideal 457 RPM，余量 11×）；更新 INDEX.yaml 和 results/README.md。

**结果**：成功率 99.19%，TTFT P90=0.135s（SLA余量91%），✅ 可上线；推荐最低 1 实例 × 8TP（HA 建议 2 实例 × 8TP = 16 卡 L20）；chart-32b **全 7 步完成**。

---

## 三、tianji-querysafety-4b-v2-3 bakv1 QPS Peak Finder Phase 1+2 完成

**背景**：新 bakv1 端点需要独立验证 SLA 合规能力（不能复用旧端点测试结论），并确认当前生产负载（每实例 7.47 RPS）是否在安全边界内。

**做了什么**：完成 Phase 1 饱和探测（con=9→18→36，peak 在 con=18，max_rps=52.6）；Phase 2 运行 10 轮自适应逼近，bracket 收敛至 [7.8554, 8.0609]（宽度 2.6% < 3%）；Phase 3 上线验证网格（4 档 linspace [7.47, 7.86]）已启动；修复主编排脚本 Phase 1→2 过渡时 checkpoint 正则无法从 markdown 表格格式提取 MAX_RPS 的问题。

**结果**：**ideal_rps = 7.8554 RPS**，与旧端点结论（8.0 RPS）高度一致，bakv1 性能相当；生产 7.47 RPS 在 SLA 边界内，余量 +5.1%。

---

## 四、在线承载量监控集成到 Dashboard

**背景**：评测结论与线上实际运行情况需要对比才有意义，但此前 Dashboard 只展示评测数据，没有实时流量数据，无法判断当前容量使用率。

**做了什么**：调研 VictoriaMetrics 指标体系（发现新旧两种 SGLang 指标格式 `sglang_num_requests_total` vs `sglang:num_requests_total`，自动 fallback），封装核心 PromQL（每日最大 RPM）；在 `serve.py` 新增 `/api/online-rpm` 接口和 Dashboard 异步 JS 加载区块，展示当前 RPM、7 日峰值、vs 评测 SLA 使用率（绿/黄/红）；制作同事可独立使用的 `scripts/demo/query_online_rpm.py` CLI 工具（零依赖，含 ASCII 柱状图）；commit `75ad8c0`（33 文件，4205 行新增）。

**结果**：tianji 总容量使用率 **91.8%**（7日峰值 3524 RPM，总容量 3840 RPM），接近红线；lingyu 使用率 42.1%（758/1800 RPM），充裕。线上数据与评测结论形成完整闭环。

---

## 五、guoxue-v2 真实数据重评启动（情况 C 新路径）

**背景**：上次 guoxue 评估使用了兜底数据，system prompt 分布与线上不一致，需换用 AI-data 平台真实导出数据（50,000 条，1.9GB）重评；同时 SLA 要求也有更新（E2E P90 < 180s，原为 150s）。

**做了什么**：新数据格式为 AI-data 平台 downloaded 格式（每行是 `list` 而非 `dict`），DataConverter 无法处理，创建 `process_guoxue_v2.py` 完全绕过 DataConverter/DataSampler，自定义 pandas 解析流程（情况 C 路径）；Phase 1 完成（peak_decode_throughput=360 t/s，max_rps=0.260 req/s）；Phase 2 启动但遭遇测试污染（COOLDOWN_SECS=60 严重不足，avg_output_len~1386 tokens 的请求积压）和 PRODUCTION_RPS 误配，修复参数（COOLDOWN→900s，DURATION→3600s）后重启，当前运行中；在 Skill 中新增情况 C 路径、DURATION/COOLDOWN 自动推算公式、测试污染警告。

**结果**：Phase 1 完成，Phase 2 运行中（每档 1h，档间冷却 15min）；两条 Skill 文档新增了情况 C 路径和长输出推理模型的测试污染防范，方法论得到完善。

---

# 📅 2026-03-23 工作日报

## 一、chart-32b Agent 调用原始数据提取交付

**背景**：chart-32b 压测数据集只包含 6,016 条直接模型调用，41K 条 Agent 框架调用因 prompt 无法还原而未纳入。算法组需要这批原始 Agent 调用记录，用于数据输入改造（`prompt2` 字段逻辑转化）。

**做了什么**：新建 `scripts/data/extract_agent_calls.py`，从 739MB 原始下载数据中过滤 `星盘普通` 模型和对应 bot_id 的 Agent 调用；二次过滤移除 700 条 `prompt2` 为空的记录（日志写入偶发丢失）；确认 307 条异常记录（model/bot_id 均为空）属于日志残缺，与文档记录 41,320 的差值得以解释。

**结果**：交付 `xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl`（**40,315 条，716MB**），prompt2 全部有效，可直接用于算法组改造。

---

## 二、guoxue EVAL_REPORT 混合部署纠正 & INDEX.yaml 双配置重构

**背景**：guoxue EVAL_REPORT.md 多处将当前部署误写为"仅 6×H20"，与实际（6×H20 + 4×L20 混合 10 实例）不符；INDEX.yaml 中 `saturation_rps` 字段存放的是 H20 数据（0.7348），但主配置标注为 8×L20，Dashboard 显示混乱。

**做了什么**：修正 EVAL_REPORT 6 处错误（摘要表、部署配置、流量说明、当前方案对比表等），新增三锚点对照表和 Phase 1 饱和探测摘要；重构 INDEX.yaml——以 `_h20` 后缀区分两套配置（L20 为主配置，H20 数据挂 `_h20` 后缀），新增 H20/L20 效率对比字段（QPS 比 2.78×，每卡 RPS 比 5.56×）。

**结果**：Dashboard 显示数据与实际部署一致；L20 vs H20 两套性能数据在同一条目中清晰可查。

---

## 三、guoxue V1 旧实验归档 & EVAL_REPORT 完全重写

**背景**：此前 guoxue 评估基于兜底数据，业务峰值口径只算了 stream 流量（43 RPM），遗漏了 MCP 八字深度的 213 RPM，导致评估结论严重低估需求（推荐 4 实例 × 8L20），与实际所需差距巨大，需用 V2 真实数据重写报告。

**做了什么**：将 4 个 V1 实验目录（使用兜底数据）移入 `results/archive/guoxue-v1-deprecated/` 并写 ARCHIVED.md；完全重写 EVAL_REPORT.md——业务峰值从 43 RPM 修正为 **256 RPM**（stream 43 + MCP 213），推荐方案从"4 实例"扩大为"**≥20 实例 × 8L20（160 卡）**"，明确 L20 为长期目标、H20 为临时过渡；修正 INDEX.yaml 中 `sla_max_qps_rps`（0.5878→0.2114）和 `sla_max_qps_rpm`（35.3→12.7）。

**结果**：guoxue 评估结论完成 V1→V2 切换，资产归档清晰，Dashboard 数据修正，报告结论可信度大幅提升。

---

## 四、guoxue L20 生产锚点补测

**背景**：Phase 3 最低档为 0.05 req/s，与 Grafana 实测生产 RPS（0.195 req/s）相差 4 倍，"生产 RPM 锚点"名不副实，需补跑实际生产负载档位。

**做了什么**：新建 `run_prod_anchor_guoxue8tp.sh`，跑单档 1 小时（0.195 req/s，843 请求，含 1.2× buffer）；分析结果时发现初始成功率显示 83.4%，经 status 分布分析确认 140 条 `status=-5` 为 TIMELIMIT buffer 未发请求，实发 703 条全部成功。

**结果**：**成功率 100%，TTFS P90=730ms（SLA 余量 51%），E2E P90=152.2s（SLA 余量 15.4%）**；Phase 3 报告新增实测生产锚点行，结论更具说服力。

---

## 五、guoxue 4H20+9L20 新部署回放分析 & EVAL_REPORT 增量更新

**背景**：业务侧将部署从 6H20+4L20 调整为 4H20+9L20（H20 释放 2 卡，换 5 张 L20），需验证新方案在实际流量下的表现，并与基线方案横向对比。

**做了什么**：确认回放测试完成（6,358 条，100% 成功率，54 分钟）；运行 `offline_analysis.py` 处理 6.3GB CSV，生成 HTML + 7 张 PNG；撰写 REPORT.md（含与 6H20+4L20 基线的 5 项指标横向对比）；用增量修改模式更新 EVAL_REPORT.md 的 5 处（摘要表、回放结论双方案表格、部署配置节、实验索引）。

**结果**：4H20+9L20 成功率 **99.89%**，TTFT P90=1.029s，E2E P90=115.5s（SLA 余量 36%）；相比基线 E2E P90 升高 14.7%，整体仍在 SLA 范围内，三月峰值 195 RPM 余量 +31%；⚠️ E2E P99=148.8s（达 SLA 的 83%），需持续监控。

> **今日整体进展**：progress.md 归档为 Vol.2（历史 4826 行已压缩入 `progress_archive_vol1.md`），guoxue 是全天主线，完成了数据纠错、资产清理、报告重写、补测验证和新方案回放分析的完整闭环。

---

# 📅 2026-03-24 工作日报

## 一、guoxue Eagle3 8×L20 QPS Peak Finder 分析归档

**背景**：昨晚 guoxue Eagle3 8×L20 三阶段压测（Phase 1+2+3）全部完成，需要生成 REPORT.md 并与 vanilla 部署横向对比，验证 Eagle3 优化的实际增益。

**做了什么**：合并 Phase 2+3 共 8 档数据跑 `qps-sweep-comparison`，生成容量曲线 HTML；生成完整 REPORT.md，补充 P50/P99 原始指标（Python 解析 token_list）、Eagle3 vs vanilla 对比表、保守/激进双建议（保守 0.28 req/s P99 友好 / 激进 0.317 req/s + 告警阈值 0.325）；归档 5 个日志目录的 README；清理测试污染数据（Phase 2 第一次运行因上轮在途请求未排空，TTFS P90=124.7s，与干净数据的 0.746s 相差 167×，作废并删除）。

**结果**：Eagle3 ideal_rps = **0.3169 req/s（19.0 RPM）**，较 vanilla 0.2114 提升 **+50%（1.50×）**；极限 RPS +40%，decode 吞吐 +59%，E2E P90 +12%（长尾加剧，P99=207.7s 超 SLA，建议保守运行）。

---

## 二、guoxue H20 Phase 3 数据有效性核查 & logs 归档清理

**背景**：`logs/` 中存在三个 `guoxue-v2-h20-phase3` 目录（3/22 两个几乎同时启动的 + 3/23 独立重测），需要判断哪个数据有效；同时 `data-pipeline/` 下积压了 58 个 log 文件，大量对应目录已删除。

**做了什么**：通过解析 token_list 计算各档位 TTFS/E2E，对比发现 3/22 并发双路版本（1754/1759）的 `qps_0.5878` 成功率仅 11.7%，timeout 1819 个，TTFS P90 高达 273s——典型并发抢占污染；3/23 独立版本（1024）全部 4 档 timeout=0，E2E 严格单调递增，确认为有效数据，删除两个污染目录；对 58 个 data-pipeline log 逐一人工精确核定（自动模糊匹配误判多，手动修正），归档 37 个孤立/过期 log，保留 21 个活跃 log。

**结果**：数据质量问题清零，有效 H20 Phase 3 数据确认；logs 目录整洁，活跃/归档分类清晰。

---

## 三、chart-32b Agent 调用 prompt2 批量转换

**背景**：算法组接收到 40,315 条 Agent 框架调用原始记录后，需要将 `prompt2`（结构化占星参数）通过转换接口还原为完整的 `[system_msg, user_msg]` 格式，才能用于后续压测数据集构建。

**做了什么**：分析转换接口（`POST /v1/chat/completions/messages`）输入输出结构，验证单条 Demo（system 2619 字符，user 98 字符）；编写 `convert_chart_agent_prompt2.py`，支持 5 并发、3 次重试指数退避、有序写出、断点续传，后台启动（PID 1200975）。

**结果**：冒烟测试 20/20 通过；后台转换中，已处理 5,956 条（14.6%），速率约 0.75 条/s，整体耗时预计约 15 小时。

---

## 四、guoxue Eagle3 4×H20 Phase 2 分析 & EVAL_REPORT 数据修正

**背景**：Eagle3 4×H20 Phase 2 已完成 2 档（rps=0.3415 和 rps=0.4519），需要分析进展，判断是否继续二分搜索；同时发现 EVAL_REPORT.md 中 H20 相关数据有三处错误需修正。

**做了什么**：分析两档结果——rps=0.3415 通过 SLA（E2E P90=44.8s，余量充足），rps=0.4519 服务端并发激增至 144（Little's Law 反推 E2E≈320s），呈现 **Eagle3 陡崖型拐点**特征（真实 ideal_rps 预计 0.38~0.42）；EVAL_REPORT 修正三处错误（服务端承载并发从错误的 70 改为正确的 57，peak decode 吞吐区分 Phase 1 实测值与 Phase 3 值，Phase 1 H20 估算精度警告从"差 4%✓"改为"差 50%✗，仅测两档导致"）；Kill Phase 2 进程、服务重启后，启动单点探测（rps=0.5878，vanilla H20 ideal_rps，约 1 小时，进行中）。

**结果**：EVAL_REPORT 数据修正完成，不再有误导性数值；Eagle3 4×H20 陡崖特征初步确认，单点探测结果出来后可继续二分锁定 ideal_rps。

---

# 📅 2026-03-25 工作日报

## 一、guoxue Eagle3 4×H20 过载确认 & 生产端点双探针分析

**背景**：guoxue H20 部署存在两条路径需要横向对比——`infra-base`（vanilla H20，相当于 Phase 3 直连）和 `infra-opti`（Eagle3 优化）。昨夜（3/24）Eagle3 探针数据已完成，今天上午还补跑了两个生产网关探针，需要完整分析并对齐报告体系。

**做了什么**：
1. **昨夜 Eagle3 探针分析**：对 `eagle3-4h20-probe-rps0.5878_20260324` 完成离线 CDF 分析 + Grafana 监控整合，撰写含 Vanilla vs Eagle3 横向对比的完整 REPORT.md；
2. **双探针离线分析**（3/25 上午新跑）：对 infra-base（Vanilla）和 infra-opti（Eagle3）各执行 `benchmark-result-analysis`，生成 HTML + 7 张 PNG + REPORT.md；
3. **报告体系对齐**（brainstorming → 方案 C+A）：更新 4 份文件——Phase 3 权威 REPORT.md 新增 §5 生产端点对比，EVAL_REPORT.md 拆分并发字段、修正 TTFT/TTFS 口径、新增 §4.6 生产端点观测节，model-context.md 新增 `h20_infra_base_probe_*` 11 个字段。

**结果**：

| 指标 | Phase 3 直连（权威）| infra-base 探针 | Eagle3 探针 |
|------|:---:|:---:|:---:|
| 成功率 | 99.91% ✅ | 100.00% ✅ | 75.15% ❌ |
| TTFS P90 | 635ms ✅ | 752ms ✅ | 3,315ms ❌ |
| E2E P90 | 114.9s ✅ | 189.6s ⚠️ | 600.6s ❌ |
| Grafana 并发均值 | ~57 | 83.6 | 256.66 |

- **Vanilla infra-base**：TTFT/TTFS 达标，E2E P90 略超 SLA（189.6s vs 180s），根因为测试期间共享背景流量 ~16 RPM 使并发从 57 升至 83.6，服务本身能力未变；
- **Eagle3 二次确认过载**：两次独立实验（3/24 + 3/25）均显示 max sustainable RPS ≈ 0.52 req/s，低于测试速率 0.5878（超载 ~11.5%），decode 吞吐（1157~1224 t/s）低于 Vanilla（1260 t/s），**Eagle3 4×H20 当前不具备 SLA 合规能力**，如需继续评估应从 ≤ 0.45 req/s 重新探针。

---

## 三、chart-32b-agent QPS Peak Finder Phase 1 双路完成 & Phase 2 启动

**背景**：chart-32b-agent 模型采用新数据集（40K+ Agent 框架调用转换后的 prompt2 数据，avg_output_len≈452 tokens），需对 8TP 和 4TP 两种部署各自从头执行 Phase 1 饱和探测，确定极限吞吐和 Phase 2 起始 RPS。

**做了什么**：并行执行 8TP（con 从 50 步进至 410）和 4TP（con 从 25 步进至 480）的饱和探测；途中修复 7 个脚本的硬编码路径（日志目录从 `logs/chart-32b-agent-*` 迁移至 `logs/xinghan-chart-32b-v1-1-agent/`），并修复 `_write_phase1_checkpoint()` 函数签名不匹配导致的 checkpoint 写入 bug；Phase 1 完成后立即启动双路 Phase 2 自适应逼近（8TP 18:19，4TP 19:00）。

**结果**：

| 部署 | 峰值并发 | 峰值 decode 吞吐 | max_rps | Phase 2 起始 RPS |
|------|---------|----------------|---------|----------------|
| 8TP  | con=400 | 2056.8 t/s     | 4.55 req/s | 5.46 req/s |
| 4TP  | con=400 | 1627.7 t/s     | 3.60 req/s | 4.32 req/s |

- 8TP/4TP 吞吐比≈1.26×（远低于理论 2×），说明 32B 模型 TP 扩展存在显著通信开销；两路 Phase 2 已后台运行中。

---

## 四、analyze_peak_finder.py 全面加固（Phase 0/Phase 1 分析精度提升）

**背景**：Phase 1 启动后发现分析脚本存在 5 个系统性问题：Phase 0 采样偏差（仅 500 条，误差最高 20%+）、无数据质量检查、Phase 1 max_rps 分母来源不明确、脚本调用链断裂（10 个 auto 脚本均未传 Phase 0 权威均值）。

**做了什么**：
1. Phase 0 从 500 条采样改为全量 tokenize，彻底消除采样误差；
2. 新增 `<think>` 比例（≥70% 合格）和 `<con>` 残留（<5% 合格）两项数据质量检查，输出"可信/有缺陷"判断；
3. Phase 0 输出 `DURATION_SECS/COOLDOWN_SECS/INIT_CON` 自动推算汇总块，可直接粘贴到脚本；
4. Phase 1 新增 `--avg-output-len-phase0` 参数，优先用 Phase 0 权威值计算 max_rps，未传时回落 Phase 1 实测值并打 ⚠️；
5. checkpoint 新增双值对比行（Phase 0 vs Phase 1 偏差、实际分母来源）；
6. 更新 SKILL.md Phase 1 CLI 用法和 checkpoint 模板；
7. 修复 10 个 auto 脚本调用链（逐一补传 `--avg-output-len-phase0`，`guoxue4h20` 额外新增变量定义）。

**结果**：`analyze_peak_finder.py` 分析精度和自诊断能力全面提升，commit `8ae4a49`；旧脚本静默回落兼容，新脚本强制校验；Phase 0 首次成为"数据质量门控"而非仅输出均值。

---

# 📅 2026-03-26 工作日报

## 一、chart-32b-agent 8TP/4TP 评估完整收尾

**背景**：昨夜 chart-32b-agent 8TP/4TP 两路 Phase 2/3 完成，今天需要合并数据、生成容量曲线和最终报告，并用真实 Agent 数据做生产回放验证，完成全流程闭环。

**做了什么**：
1. 修复 Phase 3 汇总脚本 bug（循环内误传子目录而非父目录给分析脚本），合并 Phase 2+3 各 10 档数据；
2. 生成 4TP/8TP 双组容量曲线图表（3 个 HTML），撰写完整 REPORT.md（三锚点摘要 + 8TP vs 4TP 对比）；
3. 执行 8TP 生产回放压测（Agent V2 数据集，118 RPM），分析 5,779 条结果，生成 REPORT.md + 7 张图表；
4. 更新 INDEX.yaml（`eval_status: completed_v2`）和 results/README.md。

**结果**：

| 配置 | 理想 RPS | 理想 RPM | TTFS P90@SLA 边界 |
|------|---------|---------|-----------------|
| 4TP（infra-opti）| 2.22 req/s | 133 RPM | 1,488ms（裕量 0.8%）|
| 8TP（infra）     | 3.83 req/s | 230 RPM | 1,443ms（裕量 3.8%）|
| 8TP/4TP 倍率 | **1.73×** | — | — |

- V2 数据集（含完整 Agent 工具调用序列）导致 QPS 比 V1 低约 50%，根因是 avg_output_len 大幅增加；
- **回放结果**：成功率 100%，TTFT P90=0.207s，E2E P90=14.034s，SLA 全项大幅达标，可安全支撑当前生产流量及短期增长至 ~200 RPM。

---

## 二、chart-deep-v5-2-235B 8×H20 QPS 评估启动 & relay 修复

**背景**：`chart_deep_v5-2_235B` 是新接入模型，上午完成 Phase 1 饱和探测后，relay 脚本未能自动衔接 Phase 2，需排查修复，确保后续评估自动化接力正常运行。

**做了什么**：确认 Phase 1 完成（con=60→120→180，于 con=180 饱和，PEAK_RPS=1.2911 req/s）；定位并修复 relay 脚本两个 bug——①checkpoint 文件首次出现即提前 break（此时 Phase 1 仍在继续跑后续档）；②checkpoint 格式为 Markdown 表格，旧 grep 模式不匹配触发 `set -e` 退出；清理因多次调试产生的 2~3 个重复 Phase 2 进程及污染目录；干净重启 Phase 2（14:41）。

**结果**：relay 修复落地（Bug 1/2 均已记录，防止复现）；Phase 2 单路干净运行（PID 3204661），已完成 rps=1.5493（预期过载），正在收敛第 2 档 rps=1.3582；relay 统一接管 Phase 2/3 全流程，不再需要手动干预。

---

## 三、guoxue Eagle3 4×H20 调参探针测试

**背景**：前两次测试（3/24、3/25）均确认 Eagle3 4×H20 在 rps=0.5878 严重过载（成功率 75%，E2E P90=600s），根因是 spec_accept_length≈0.67 处于中等接受率，过多 rejected token 浪费算力。参考 TurboSpec 论文 §4.1.2 结论，减少投机 token 数在中等接受率下可提升 goodput，用户据此缩短了 speculative 参数。

**做了什么**：服务端将 speculative 参数从 `steps=3, draft_tokens=4` 调整为 `steps=2, draft_tokens=3`；编写新探针脚本（与前次参数完全一致，仅服务端配置变化），后台启动（18:46，PID 3384463），预计 19:46 完成。

**结果**：探针运行中，完成后与 3/25 探针对比 TTFS/E2E 变化量，判断调参是否能将 max_rps 从 ~0.52 提升至 0.5878 以上。

---

# 📅 2026-03-27 工作日报

## 一、chart-deep-v5-2-235B 评估：发现并修复 128 并发限制导致的全链路低估

**背景**：昨日（3/26）chart-deep-v5-2-235B 的 Phase 1 于 con=180 显示"饱和"，Phase 2 首档 rps=1.3582 判定为"FAIL"，结论看起来异常保守。今天深入排查发现根因——服务端配置了 `--max-running-requests 128`，当 con>128 时内部并发被硬截断，造成"假饱和"和"假失败"，导致 max_rps 整体低估约 23%。

**做了什么**：修复三个脚本的问题（更新 SERVER_URL、删除硬编码 `MAX_REQUESTS=5621`、支持 `PREV_DIR`/`INIT_LO` 环境变量注入透传）；在新的无限制服务上从 con=180 重跑 Phase 1（历经 con=180→270→283→297→311→326，于 con=326 确认饱和）；Phase 1 完成后 relay 自动触发 Phase 2（18:57 启动），以旧 PASS 值 1.3360 为 LO 起建 bracket。

**结果**：

| 指标 | 旧跑（受 128 限制） | 新跑（无限制） | 变化 |
|------|-----------------|-------------|------|
| 峰值 decode 吞吐 | 1298.9 tok/s | **1603.6 tok/s** | **+23.5%** |
| max_rps_estimate | 1.2911 req/s | **1.5940 req/s** | **+23.5%** |
| 真实饱和并发 | 128（人为截断）| **326** | — |

Phase 2 第一档 rps=1.4696 已 FAIL（TTFS P90=1838ms），bracket 收敛至 [1.3360, 1.4696]，下一档 rps=1.4012 正在冷却后探测，预计今晚完成收敛。

---

## 二、guoxue Eagle3 4×H20 SLA 边界定位完成

**背景**：此前（3/24~3/25）多次确认 Eagle3 4×H20 在 rps=0.5878 严重过载（成功率 75%），今天通过调参后的服务（speculative steps=2, draft_tokens=3），以多档位探针逐步逼近真实 ideal_rps。

**做了什么**：补充分析旧 Phase 2 rps=0.3415 档（SLA 全达标，E2E P90=44.8s）；依次运行 rps=0.40（20 分钟探针）和 rps=0.43（22 分钟探针），全程监控 TTFS/E2E 变化；中间经历进程残留导致多次重启（每次用 `pgrep` 确认清空后重新发起），最终获得干净数据。

**结果**：

| RPS | 成功率 | TTFS P90 | E2E P90 | 判定 |
|-----|--------|----------|---------|------|
| 0.5878（3/25） | 75.15% | 3.315s | 600.6s | ❌ 严重过载 |
| 0.43（今日） | 100% | 1.192s | 182.1s | ❌ 临界超标（+1.1%）|
| **0.40（今日）** | **100%** | **0.901s** | **107.2s** | **✅ ideal_rps** |
| 0.3415（Phase2）| 100% | 0.594s | 44.8s | ✅ |

**ideal_rps = 0.40 req/s（24 RPM）** 定位完成，SLA 边界区间 `0.40 < ideal_rps < 0.43`；下一步执行 Phase 3 四点网格验证后出最终报告。

---