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