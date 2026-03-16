# Deployment migration model evaluation
_Exported on 2026/3/12 at GMT+8 11:52:24 from Cursor (2.5.26)_

---

**User**

我有一个相关目前这个工程项目主要是来应对部署迁移模型评估的工作，你看出了线上平台部署操作以外，包括写本地实例测试验证，数据处理，写远端访问调用， 回放测试，QPS压力测试基本上流程论都是一套内容，而且切换不同模型从测试需要做量化汇报的style 都是一套风格，所以这个工作就会有点越来越拧螺丝的感觉，我这2天做完一套流程后，基本也就熟络了，目前想进入下一阶段，将其scaling 。首先我们在third_party 使用了在之前每个执行工作环节中细节内容拆分组装的repo 来完成步骤性质的搭建 ，目前结果分析我也可以产出量化的表格跟内容来交给你去分析汇总，
我现在想整个项目先来完成 skill 如何？ 我们可以边看边聊，看看哪些内容需要做调整，哪些组件需要做更新，或者你觉得哪些步骤需要进一步完善。 @.cursor/skills/brainstorming/SKILL.md  @.cursor/skills/writing-skills/SKILL.md 
@clingo/docs 目录交给你来做好规划，你先自行梳理一番，我休息10分钟后找你来讨论你 Need&TODO&IDEA 

---

**Cursor**

我先读取相关技能文件和探索项目结构，然后系统整理规划内容。

现在让我全面探索项目结构，特别是 `clingo/docs` 目录和整个工程布局。

很好，现在我对整个项目有了清晰的全局视角。让我再看看 `clingo/` 目录是否有 `docs` 子目录，以及 `progress.md` 的关键内容。

现在我已经掌握了项目全貌。让我来整理规划内容，写入 `clingo/docs/`。

规划已完成，`clingo/docs/` 目录结构已建立。以下是我梳理的核心内容，等你回来讨论：

---

## 我整理的判断

### 项目本质

你说得很准——这是一套**参数可变、结构固定的评估流水线**。每个新模型都要走同样8步，只有模型名、GPU配置、端口、模型类型会变。这正是 Skill 化最有价值的场景。

---

### 已创建的文档

```
clingo/docs/
├── README.md               ← 项目概览 + 已跑通模型清单
├── need-todo-idea.md       ← 核心规划讨论文档（见下方摘要）
├── skills/
│   └── skills-roadmap.md  ← 5个Skill候选清单 + 优先级 + TDD交付标准
├── workflow/               ← 待填充
└── models/                 ← 待填充
```

---

### Need（痛点）摘要

| # | 痛点 | 严重程度 |
|---|------|----------|
| N1 | 每个新模型脚本几乎从零开始写 | 🔴 高 |
| N2 | `third_party/` 为空，工具层边界不清 | 🟡 中 |
| N3 | 结果分析靠手工整理，脚本写死路径 | 🟡 中 |
| N4 | 探测脚本无标准输出，无法存档对比 | 🟡 中 |
| N5 | Skill 体系空缺 | 🔴 高 |

---

### Skill 候选（共5个，已排优先级）

| 优先级 | Skill 名 | 解决的痛点 |
|--------|----------|-----------|
| P0 | `llm-service-probing` | 探测脚本结构标准化 |
| P0 | `qps-benchmark-sweep` | QPS 扫描方法论沉淀 |
| P1 | `traffic-dataset-prep` | 数据处理管道可复用 |
| P1 | `llm-deployment-docker` | Docker 部署参数速查 |
| P2 | `model-evaluation-workflow` | 顶层全流程编排（依赖前4个） |

---

### 等你回来讨论的6个问题

见 [`clingo/docs/need-todo-idea.md`](clingo/docs/need-todo-idea.md) 的"讨论议题"节，核心是：
1. `third_party/` 怎么管理？
2. `tmp/` 下的脚本要重组吗？
3. 第一个 Skill 从哪个开始？
4. 是否需要 HTML Dashboard？
5. 模型骨架生成器 `init_model.py` 有没有吸引力？
6. 模型档案要统一格式吗？

你休息好回来，我们逐个过。

---

**User**

关于Need
N1 你说每个模型脚本几乎从0开始我没明白
N2 目前 third_party 我看 /mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party 我软连接了几个repo了吧？
N3 我明白缺失目前分析结果包括使用analysis 分析执行benchmark 调用client结果后是我自己去截图将结果放在 results 指定任务的目录下的
N4 目前执行探测脚本是指什么？ 你觉得需要什么标准输出？
N5 现在我们不就是在构建这个skill体系吗？ 每个环节我们都可以深入来做建模修改

另外关于你想到几个问题 ，"讨论议题"节，核心是：
1. 目前 third_party 应该是软连接来关联 我任务相关流程需要的核心模块，也方便你理解。
2. 目前tmp 的脚本都是这2天执行 针对迁移任务做的数据处理&本地化部署启动脚本以及执行QPS测试部分脚本吧，重组的话我目前没有想好要如何来做？你可以给我建议我来思考判断
3.第一个skill 我们可以先从数据转换来梳理你觉得呢？
4. 这个需求的出发点是什么？
5.你的吸引力具体是指？
6.模型档案是指什么？


---

**Cursor**

先让我看看 `third_party/` 和 `README.md` 的实际内容，再逐条回答你。

好，逐条把话说清楚。

好，现在情况清楚了。逐条回答：

---

**N1 — "从零开始"表述不准确**

我的意思是：`probe_models.py` → `probe_tianji_querysafety.py` 这两个脚本结构相似，但是靠手动复制然后改，没有一个参数化的模板。不是真的从零，而是 **copy-paste-modify**，容易改漏，也没有结构强制。你接下一个模型还得再做一次。

这和"有无模板"是两件事，我表述不精准，订正。

---

**N2 — third_party 是软链接，我之前看错了**

实际是：
- `third_party/data_analysis` → `data_analysis` 仓库（含 `scripts/analysis/data_processor/gen_data/tools`）
- `third_party/speculative-decoding-benchmark` → benchmark 工具仓库（含 `modao/src/benchmark/scripts`）

这个设计很清晰，软链接的方式正好解耦了工具层和本工程。N2 不是痛点，是已经解决好的事情，我的判断有误，删掉这条。

---

**N3 — 分析流程已理解**

流程是：benchmark 执行 → `data_analysis` 工具处理 → 你截图 → 放进 `results/` 对应目录。

真正的缺口不是工具，而是**截图这一步是手动的，没有自动存档**，导致结果只存在于你的截图里，没有结构化数据可以跨模型对比。先记着，不是紧急问题。

---

**N4 — 探测脚本的"标准输出"是指**

目前两个 probe 脚本跑完，结果全打到 stdout，没有文件存档。我的意思是：

```
目前：  跑 → 看屏幕 → 结束，结果消失
建议：  跑 → 看屏幕（保持）+ 自动写 results/<模型名>_probe_<date>.json
```

这样下次接第三个模型的时候，可以直接把三个 JSON 拿出来做横向对比，不用靠记忆或翻日志。但这是个**锦上添花**的点，不影响当前流程，先留着。

---

**N5 — 是的，我们就在做这件事**

确认，这条就是当前对话的目标，不需要单独列出来。

---

然后是你的六个问题：

**Q1** 软链接模式已理解，设计好的，保持。

**Q2 — tmp/ 重组建议**

现在 `tmp/` 里混了两类东西：
- **Shell 脚本**（部署启动、QPS 测试），本质是"对特定模型的配置化操作"
- **Python 脚本**（探测、数据处理、合并），本质是"执行特定任务的一次性代码"

这两类其实性质不同。我的建议：

```
scripts/              ← 从 tmp/ 提升一级，按功能分目录
  deploy/             ← 所有 Docker 启动脚本（start_*.sh）
  benchmark/          ← 所有 QPS 测试脚本（run_*.sh）
  probe/              ← 所有探测脚本（probe_*.py）
  data/               ← 所有数据处理脚本（process_*.py, make_*.py, fix_*.py）
  analysis/           ← 合并/分析脚本（merge_*.py）
tmp/                  ← 真正的草稿区，只放"还没稳定"的东西
```

**好处**：下次接新模型的时候，直接去 `scripts/deploy/` 找模板，去 `scripts/data/` 找数据处理脚本改参数，不用在一堆文件里翻。

你觉得这个方向对吗？如果方向认可，我可以把现有脚本直接迁移过去。

**Q3 — 第一个 Skill 从数据处理开始**

同意这个选择，理由：

1. 数据处理这条链路逻辑最复杂（jsonl→采样→泊松插值→拼接→脏数据过滤），最容易出错，最值得固化
2. 它的输入输出定义清晰（原始 JSONL 进，带时间戳的 CSV 出），容易写测试用例
3. 和模型类型无关，通用性最强

所以：第一个 Skill = `traffic-dataset-prep`

**Q4 — HTML Dashboard 的出发点**

出发点是：你现在每次出报告要截图，截图不能搜索、不能对比。一个 HTML 文件可以把所有图表和数据打包成自包含文件，直接发给对方看，也方便自己归档。

但这是一个**额外需求**，如果截图工作流目前没有痛感，完全可以不做。你觉得目前截图交付有什么不满意的地方吗？还是还好？

**Q5 — `init_model.py` 生成器**

重新表述：就是一个命令行工具，你输入模型名/端口/GPU列表，它帮你自动生成那一套脚本（启动脚本+探测脚本+模型档案），不用手动复制改参数。

这和你 Q2 提到的重组方向配合——如果脚本都有了统一目录和结构，生成器就有模板可以填。

你觉得这个"自动生成脚本骨架"的方向有用吗？还是你倾向于手改更灵活？

**Q6 — 模型档案**

就是给每个迁移的模型建一个"信息卡"，记录：

```
- 模型名称 / 版本
- 部署配置（GPU 数量、TP 配置、端口、镜像）
- 模型行为特征（通过探测总结的：输出风格、响应时间分布、边界行为）
- 压测结论（最大承载 QPS、TTFT P90 基线）
- 已知问题 / 注意事项
```

类似一个"技术说明书"，下次业务方问"这个模型能承载多少并发"，直接翻档案。

你觉得这个东西有没有实际价值？还是目前 `project_status.md` 已经够用？

---

**User**

N1 的这个内容我大致理解你的出发点，我说下当初做 probe_*.py 脚本的动机，实际上是目前有的交付迁移的模型可能没有提供业务数据，我自己不知道这个模型是用来做什么，所以我想使用探针query形式去反向了解这个模型在业务场景是做什么的，之后的流程任务上一般都是有业务数据路径来提供,目前定义了是放在 /mnt/ai-infra/datasets 目录下，目前还构建不完善，还在逐步构建

N2 你理解就过了哈

N3 目前的流程是： data_analysis 处理业务数据 -> 部署平台实例部署(目前是必须手动来执行，应该给你的就是可以调用的URL）-> benchmark 执行根据相关模型来构建调用执行 -> 使用 @third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/src/llm_benchmark/analysis 内容来做分析或者执行@third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/src/llm_benchmark/analysis/analysis 相关工具来分析 -> 截图 → 放进 results/ 对应目录
我就在想目前的截图实际上是 在分析工具中构建的内容我在浏览器上来截图获取的，里面是有很多结构化的数据，但是实际上都是在之前使用benchmark 执行的请求调用结果做了从请求粒度统计到一次调用环境下的统计可视化以及结构化执行，所以我想之后做截图执行需要去参考目前工具调用将中间过程从内容中抽取出来做可视化。

N4 探测脚本问题我在N1上解释过动机了，实际上你明白我的需求就知道应该要做什么了

关于问题讨论：
Q1过

Q2 目前的tmp整理目前先用立马迁移，之后我们执行到相关步骤梳理的时候再回过头来执行，比如我们现在第一步整理数据处理的skill 实际上是可以做 data 部分的内容的。

Q3 前后呼应 Q2

Q4 就是目前的截图内容实际上都是 在分析执行的python脚本阐述的html中将内容做的截图 相信之后在梳理 分析结果获取内容中我们会深入来做相关内容修改。

Q5 感觉这个需求貌似没什么用吧？

Q6
这个model-card可以有。但是它跟 project_status.md 应该没有什么关系，后者是我使用来AI会话 工作记录的。


---

**Cursor**

理解了，几个关键认知更新：

- **probe 脚本**：是在没有业务数据时用来反向推断模型用途的探针工具，不是常规流程
- **分析工具**：benchmark 跑完 → llm-benchmark analysis 生成 HTML → 你从浏览器截图；未来方向是从中间结构化数据直接导出
- **第一个 Skill**：数据处理，同步整理 `tmp/` 的 data 类脚本
- **model-card**：有价值，独立于 project_status.md

先更新文档，把讨论结论固化，然后看数据处理脚本准备开始第一个 Skill。

现在数据处理链路看得很清楚了。先把 need-todo-idea.md 修正，然后直接开始第一个 Skill。

现在来看 `process_ziwei_full.py`，把完整数据处理链路摸清楚，然后开始写第一个 Skill。

数据处理链路看完了，现在完整清楚了。整条管道分 5 步，工具全在 `data_analysis` 里。

开始写第一个 Skill：

写完了，给你看下最终的 Skill 结构，然后讨论几个问题：

417 字，在目标范围（<500）内。

---

**Skill 覆盖了以下内容：**

| 步骤 | 覆盖方式 |
|------|----------|
| JSONL → CSV | GlobalConfig + DataConverter API 示例 |
| 峰值窗口采样 | DataSampler._select_data 用法 |
| 时间戳拼接 | 手动实现代码（>5min 间隔检测 + 平移） |
| 泊松插值 | DataInterpolator.interpolate_by_peak 完整参数 |
| 脏数据过滤 | has_list_content 函数 + 过滤模式 |
| 验证 | 每步 checklist 表格 |
| 文件命名 | 命名约定一览 |

---

**有几件事需要你确认：**

**1. `source_file` 参数的理解是否正确？**

插值时，`source_file` 应该是"含完整 messages 内容的源数据池"，当插值需要填充更多行时从这里借数据。我的理解是用某天的完整 CSV（比如 03-04 那天）。是这样吗？

**2. `read_only_time` 这个参数的精确含义？**

我理解是：`True` = 只读时间戳（快，不拉 COS URL），`False` = 完整拉取 prompt 内容（慢）。但 sampler 里用 `read_only_time` 是影响它找哪个输入文件吗？（比如 True 找 `_timestamps.csv`，False 找 `_all.csv`？）

**3. `tmp/` 中的 data 类脚本要现在迁移到 `scripts/data/` 吗？**

你之前说"立马迁移"，我可以马上做。但我想先确认目录结构的想法——根目录下直接建 `scripts/`，还是放在 `tmp/scripts/` 下再加子目录？

---

**User**

1. source_file 你是说做柏松差值的时候的输入吗？ 我觉得可以使用  消除段间大间隔 后的csv 来当输入
2.read_only_time 参数理解是对的，这个参数实际执行的时候都是默认为False，为True在获取数据做调试来检查请求时间来模拟回放请求来的时候
3.立马迁移。

---

**Cursor**

好，三件事一起做：更新 SKILL.md、迁移脚本目录。先确认现有脚本清单。

迁移完成。同步更新 SKILL.md 里关于 `source_file` 和 `read_only_time` 的表述：

现在写 `scripts/README.md`，把目录结构说清楚：

完成，汇总一下这一轮做了什么：

---

**已完成**

1. **SKILL.md 修正**
   - `source_file`：改为用拼接后的 CSV 自身（而不是独立源文件）
   - `read_only_time`：标注生产默认 `False`，`True` 仅调试用

2. **脚本目录迁移**（`tmp/` → `scripts/`）
   ```
   scripts/
   ├── deploy/     3 个 Docker 启动脚本
   ├── benchmark/  4 个 QPS 测试脚本
   ├── probe/      3 个探测 / 连通性脚本
   ├── data/       4 个数据处理脚本
   └── analysis/   1 个结果合并脚本
   ```
   `tmp/` 保留原文件不动（作为草稿区备份，你可以之后手动清空）

3. **`scripts/README.md`**：把每个目录和脚本的用途写清楚，下次找脚本直接看这里

---

**下一步方向：**

- 继续做第二个 Skill（`llm-deployment-docker`），内容最简单，可以快速完成
- 或者先把 `clingo/docs/workflow/model-onboarding.md` 的 SOP 写出来，把现有全流程固化下来

你倾向哪个？

---

**User**

先把 clingo/docs/workflow/model-onboarding.md 的 SOP 写出来，把现有全流程固化下来

---

**Cursor**

先把现有流程的关键脚本都过一遍，再写 SOP。

现在有足够的信息了。开始写 SOP：

写完了，确认一下字数和结构完整性：

SOP 已完成，307 行，覆盖完整流程。结构如下：

---

**`clingo/docs/workflow/model-onboarding.md` 内容概览**

| 章节 | 核心内容 |
|------|----------|
| **总览** | 6步流程图 |
| **Step 0** | 信息收集清单（模型路径/GPU/TP/数据/URL）|
| **Step 1** | 启动脚本写法 + 健康检查，含 TP/PCIe 注意事项 |
| **Step 2** | 探测脚本结构（5节），触发条件：无业务数据 |
| **Step 3** | 数据处理两条路：线上 JSONL（完整 5步）vs ShareGPT（convert 脚本）|
| **Step 4** | 远端 endpoint 验证 checklist |
| **Step 5** | Benchmark 三种策略 + QPS 档位设计原则 + 后台执行命令 |
| **Step 6** | 结果合并 → 分析工具 → 归档目录 → 4个关键指标判断标准 |
| **接入 Checklist** | 6步打勾清单，下次接模型直接用 |
| **环境说明** | 所有路径汇总 |

---

**有几个地方需要你帮我确认或补充：**

1. **Step 3 情况 A 的 Python 脚本路径**：我写的是 `scripts/data/process_<model-name>_full.py`，但现有的是 `process_ziwei_full.py`，针对不同模型你会新建脚本还是复用并改参数？

2. **Step 6 的分析工具具体命令**：目前我写的是占位格式（`python modao/src/... --input ...`），你知道具体调用的是哪个 Python 文件吗？就是那个生成 HTML 报告的命令。

3. **`convert_sharegpt_to_csv.py` 的定位**：这个脚本在 `third_party/speculative-decoding-benchmark/temp_file/` 下，是 benchmark 工具自带的，不是你写的，放在 SOP 里直接引用这个路径 OK 吗？还是应该也迁移到 `scripts/data/`？

---

**User**

稍微暂时一下目前关于 model-onboarding.md 的 SOP 内容，我觉得之前完成的@.cursor/skills/traffic-dataset-prep  不仅仅在.cursor/skills 目录下要有一份对应在当前项目的软连接 它实际的存储是否需要放在@clingo/docs/skills ，并且你顺便更新一下@clingo/docs/skills/skills-roadmap.md ？ 我待会要用一个新的业务数据jsonl来测试一下.

---

**Cursor**

好问题，这是个存储架构问题。逻辑是：`clingo/docs/skills/` 是项目文档的真实存储，`.cursor/skills/` 是 Cursor IDE 的加载目录，后者用软链接指向前者。

马上实施：

软链接正常。现在更新 `skills-roadmap.md`：

完成。整理一下现在的架构：

---

**存储架构确认**

```
clingo/docs/skills/                    ← 真实存储
  traffic-dataset-prep/
    SKILL.md                           ← 内容在这里
  skills-roadmap.md

.cursor/skills/
  traffic-dataset-prep  →  软链接到 clingo/docs/skills/traffic-dataset-prep
  brainstorming/                       ← 通用 Skill，保持原样
  writing-skills/                      ← 通用 Skill，保持原样
```

---

**`skills-roadmap.md` 更新了什么**

- 加入了存储架构说明（真实存储 vs 软链接）
- `traffic-dataset-prep` 标记为 ✅ 完成，并注明当前状态是"🔄 验证中（新业务数据实测）"
- 后续 Skill 的计划内容更具体（参考了你实际的脚本）
- 加入了新 Skill 的操作规范：先建 `clingo/docs/skills/<name>/`，再建 `.cursor/skills/` 软链接

---

好，你现在用新的业务数据 JSONL 来跑一遍。跑的过程中遇到 `traffic-dataset-prep` Skill 没有覆盖到的情况，告诉我，我们做 REFACTOR 补充进去。

---

**User**

OK，回到你上一个对话的结果，实际上我已经使用@clingo/docs/skills/traffic-dataset-prep 尝试在新给定的jsonl业务数据做了测试， 完成了预期的输出结果，
所以你可以根据这个skill 来判断 你是否还需要确认
```
Step 3 情况 A 的 Python 脚本路径：我写的是 scripts/data/process_<model-name>_full.py，但现有的是 process_ziwei_full.py，针对不同模型你会新建脚本还是复用并改参数？
```

2.问题2 分析工具 我记得是调用 
```
analysis --host 0.0.0.0 --exp /mnt/ai-infra/users/wnd/workspace/execute/guofan/logs/ziwei_4tp_qps_20260310_150343
```
对benchmark 结果进行加载分析的一个客户端页面，你可以通过查看
@third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/src/llm_benchmark/analysis 工具说明以及代码来了解详情
3.关于third_party/speculative-decoding-benchmark/temp_file/convert_sharegpt_to_csv.py
是我之前做训练的时候想将训练后的模型做验证，从测试集中转换数据使用的，我们目前给的jsonl 不是 sharegpt 也不是 openai format 所以这个脚本对目前数据转换没有作用。

---

**Cursor**

先看分析工具的代码，再一起更新 SOP 和路线图。

现在情况全清楚了。`process_henpan_tarot_full.py` 已经在遵循 Skill 走了，同时它暴露了一个 Skill 还没覆盖的关键细节：`model_list` 必须包含中文别名，否则只能捞到 31% 数据。

三件事一起做：

1. **SKILL.md REFACTOR**：补充 `model_list` 中文别名陷阱 + `income_time` 来源
2. **model-onboarding.md**：修正 Step 3 脚本模式、Step 6 分析工具命令、删除 ShareGPT 情况
3. **skills-roadmap.md**：标记 traffic-dataset-prep 验证通过

Skill 已经是最新的（208 行，包含模型别名陷阱和 Step 6 README 文档步骤）。现在集中更新 model-onboarding.md 和 skills-roadmap.md：

现在更新 skills-roadmap.md，把 traffic-dataset-prep 标记为完全验证通过：

三件事全部完成，汇总：

---

**本轮变更**

**`traffic-dataset-prep` SKILL — GREEN → REFACTOR 完成 ✅**

已通过两个模型（ziwei-32b + hepan-72b）实测验证，REFACTOR 阶段补充了三个在 ziwei 时未暴露的问题：

| 补充内容 | 背景 |
|----------|------|
| `model_list` 中文别名陷阱 | 仅用英文名只捞到 31% 数据 |
| `income_time` 来源字段说明 | `messages[0].time` 或 `request_info.session_time` |
| 步骤6 README 输出规范 | 每次处理后写交付说明文档 |

**`model-onboarding.md` 三处修正**

| 位置 | 修正内容 |
|------|----------|
| Step 3 脚本模式 | 每模型新建专属脚本（copy + 改配置块），注明遵循 Skill |
| Step 3 决策表 | 加入 `MODEL_LIST` 别名验证步骤 |
| Step 6 分析工具 | 改为正确命令：`analysis --host 0.0.0.0 --port 8050 --exp <logs-dir>` |
| Step 3 删除 | ShareGPT 情况 B（与当前 JSONL 格式无关）|

**`skills-roadmap.md`** — traffic-dataset-prep 标记为 ✅ 已验证，时间线更新

---

**User**

那么接下来做什么？

---

**Cursor**

看一下当前状态再给建议：

现在项目的全貌很清晰了：

---

**各模型当前位置**

| 模型 | 数据 | 部署脚本 | Benchmark 脚本 | 状态 |
|------|------|----------|----------------|------|
| ziwei-32b | ✅ 完整 | ✅ | ✅ 已跑完 | ✅ 全流程完成 |
| ziwei-8b | ✅ 完整 | ✅ | ✅ | ✅ 全流程完成 |
| tianji-querysafety-4b | ⏳ 等待业务数据 | ✅ | ⬜ | 探测完成，卡在数据 |
| **henpan-72b** | **✅ 数据已就绪** | **⬜ 没有** | **⬜ 没有** | **数据完成，后续全缺** |

你现在打开的是 `tianji-querysafety-v2-3-system_prompt.txt`——是业务数据到了吗？

---

**两个方向，选一个：**

---

**User**

B ，开始做吧但是目前给的数据不是jsonl 内容 而是给的 tianji-querysafety-4b-v2-3_26030320_26030402_Sheet1.csv 以及对应的@datas/tianji-querysafety-v2-3-system_prompt.txt  
所以就不是走 json->csv这条路径了，而是 通过csv 中的  query 内容 将其填充到 @tianji-querysafety-v2-3-system_prompt.txt (430-431)  的 template 模版结构上
所有构建测试csv 的输入貌似就需要做改变了对吧？

---

**Cursor**

先看系统提示模板结构和数据 CSV 格式。

现在情况完全清楚了。

数据结构：
- CSV：281,443 行，字段 `user_id / sessionid / times(ms) / query / result`
- `times`：毫秒时间戳 → 需转成 `income_time`
- 系统提示末尾 `{{query}}` → 替换为实际 query → 构成完整 `messages`

这是一条**全新的数据处理路径**，需要在现有脚本和 Skill 里都补充进去。一起做：

先快速看一下 `times` 字段的实际分布范围，确认时区和峰值窗口：

数据情况清楚了：
- 仅 6 小时（03-03 20:00 ~ 03-04 02:00）
- 峰值 **2168 RPM**（03-04 00:xx），比 ziwei 高两个数量级
- 不需要多天拼接，不需要泊松放大，数据本身已经足够多

路径完全不同：没有 DataConverter，直接 CSV → 模板填充 → messages。开始写脚本：

先跑一下验证：

跑通了。现在更新 SKILL 和 README：

全部完成。结果汇总：

---

**数据处理结果**

| 文件 | 行数 | 用途 |
|------|------|------|
| `_peak30min.csv` | 44,099 行，897 MB | ★ 压测推荐，峰值 2168 RPM |
| `_all.csv` | 281,435 行，5.7 GB | 全量备用 |

**这条路径与情况 A 的核心区别：**

| | 情况 A（JSONL）| 情况 B（CSV + 模板）|
|--|---|---|
| 数据来源 | 线上日志 JSONL | 业务方 CSV |
| messages 构建 | DataConverter（拉 COS URL）| `{{query}}` 模板填充 |
| 时间字段 | JSONL 内嵌 | `times`(ms) → Asia/Shanghai |
| 是否需要泊松插值 | 通常需要（RPM 低）| 不需要（峰值 RPM 已达 2168）|
| 文件体积 | 正常 | 大（系统提示 per-row）|

**SKILL REFACTOR 已完成**：`traffic-dataset-prep` 新增情况 B 路径说明、核心实现代码、三条新的常见错误（占位符未替换、体积爆炸、时区偏移）。

---

下一步：给 `tianji-querysafety` 写 benchmark 脚本，然后可以开始压测了。要继续吗？

---

**User**

OK ，那就先使用 tianji-querysafety-4b-v2-3_peak30min.csv 来做 压力测试流程吧，我已经部署了
https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23/v1/chat/completions 

的sglang 调用服务，我希望你能从 QPS 6.0 开始将到 4.0 ， 设置30组试验，每次跑差不多45分钟， 写一个调用脚本来做测试，就写在@scripts/benchmark  目录吧

---

**Cursor**

先看一下现有 start 脚本里的模型路径，再生成 30 个 QPS 档位：

模型路径确认。30 档 × 45min = 23h，数据集 44,099 条够用（每档最多 16,200 条）。开始写脚本：

语法检查通过。同步更新 `scripts/README.md`：

脚本就绪。几个关键信息：

---

**脚本概览**

| 参数 | 值 |
|------|-----|
| QPS 档位 | 6.00 → 4.00，30 档，步进 ~0.069 |
| 每档时长 | 2700s（45min）|
| NUM_PROMPTS | 10,800 ~ 16,200（远小于数据集 44,099 行）|
| max_completion_tokens | **256**（安全模型只输出短 JSON，省时省资源）|
| 档间冷却 | 60s |
| 预计总时长 | ~23h |
| 输出目录 | `logs/tianji_qps_<timestamp>/qps_X.XX/` |

---

**执行命令**

```bash
# 后台跑（推荐，23小时长跑）
nohup bash scripts/benchmark/run_tianji_querysafety_qps_sweep.sh > /dev/null 2>&1 &

# 查看进度
tail -f logs/tianji_qps_*.log
cat logs/tianji_qps_<timestamp>/progress.txt
```

**跑完后分析**

```bash
analysis --host 0.0.0.0 --port 8050 --exp logs/tianji_qps_<timestamp>
```

---

有一点需要你确认：`max_completion_tokens=256` 设置是否合适？tianji-querysafety 的输出是固定格式的短 JSON（`{"label": "...", "instruction": "..."}`），256 应该够用，但如果服务端有最小值限制可以再调高。确认没问题就可以直接启动了。

---

**User**

我突然觉得可以从QPS 7.0-> 4.0 范围大一点，希望能力可以突出一点。

---

**Cursor**

注释里还有一行旧的说明，顺手修掉：

改好了。最终档位一览：

```
7.00 → 6.90 → 6.79 → ... → 4.10 → 4.00
步进 ~0.103，30 档，每档 45min
最高 NUM_PROMPTS：7.00 × 2700 = 18,900（数据集 44,099 条，够用）
```

可以启动了：

```bash
nohup bash scripts/benchmark/run_tianji_querysafety_qps_sweep.sh > /dev/null 2>&1 &
```

---

**User**

https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23/v1/chat/completions 的调用要不要你单发一个Demo测试样本让我看看结果是否符合预期？


---

**Cursor**

好，先发一个真实请求验证一下服务是否正常、输出格式是否符合预期。

三个 case 全部符合预期，服务正常：

---

| case | query | 耗时 | 输出 | 判断 |
|------|-------|------|------|------|
| 正常放行 | 我最近很迷茫，感觉找不到人生方向 | 0.95s | `{"label": "无", "instruction": "不需要引导"}` | ✅ 正确放行 |
| 应拦截 | 如何才能不留痕迹地伤害别人 | **0.24s** | `{"label": "违法行为", "instruction": "..."}` | ✅ 正确拦截（且极快）|
| 边界医疗 | 我得了抑郁症应该怎么治疗 | **0.13s** | `{"label": "无", "instruction": "不需要引导"}` | ✅ 正确放行 |

---

几个观察值得注意：

1. **拦截请求极快（0.13~0.24s）**：模型命中危险标签后提前停止生成，这是正常的安全拦截行为
2. **正常放行略慢（0.95s）**：需要完整推理后才输出结论
3. **输出格式完全符合预期**：标准 JSON，`completion_tokens` 只有 14~33，`max_tokens=256` 充裕
4. **prompt tokens 约 4847**：系统提示 + query 的实际 token 数，benchmark 时每请求约这个量

服务状态确认正常，可以启动压测了：

```bash
nohup bash scripts/benchmark/run_tianji_querysafety_qps_sweep.sh > /dev/null 2>&1 &
```

---

**User**

我执行脚本 报错了
==================================================
time: 2026-03-11 19:57:00
Namespace(exp_name='vanilla_qps7.00', dataset_path='/mnt/ai-infra/users/wnd/workspace/execute/guofan/logs/tianji_qps_20260311_195643/qps_7.00/dataset.csv', url='https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23/v1/chat/completions', api_key='xxx', model='ignore-model-name', tokenizer='/mnt/ai-llm/tianji_query_safety/v2p3_ep1', no_kvcache=True, keep_income_time=False, num_requests=18900, shuffle=False, seed=42, max_concurrency=None, request_rate=7.0, request_time_limit=None, max_completion_tokens=256, temperature=None, top_p=None, logprobs=False, top_logprobs=None, output_dir='/mnt/ai-infra/users/wnd/workspace/execute/guofan/logs/tianji_qps_20260311_195643/qps_7.00')
==================================================
启用了避免kv缓存命中的功能，向message中加随机前缀: (3283c74e-3c4c-4ba8-8790-479b761a4866, 回答时请忽略这个UUID前缀)

^MPreparing dataset:   0%|          | 0/18900 [00:00<?, ?it/s]Traceback (most recent call last):
  File "/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/lib/python3.10/site-packages/pandas/core/indexes/base.py", line 3812, in get_loc
    return self._engine.get_loc(casted_key)
  File "pandas/_libs/index.pyx", line 167, in pandas._libs.index.IndexEngine.get_loc
  File "pandas/_libs/index.pyx", line 196, in pandas._libs.index.IndexEngine.get_loc
  File "pandas/_libs/hashtable_class_helper.pxi", line 7088, in pandas._libs.hashtable.PyObjectHashTable.get_item
  File "pandas/_libs/hashtable_class_helper.pxi", line 7096, in pandas._libs.hashtable.PyObjectHashTable.get_item
KeyError: 'prompt'

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/mnt/ai-infra/users/wnd/workspace/execute/guofan/.venv/bin/benchmark", line 10, in <module>
    sys.exit(main())
  File "/mnt/ai-infra/users/wnd/workspace/execute/speculative-decoding-benchmark/3rdparty/llm-benchmark/src/llm_benchmark/benchmark/benchmark.py", line 431, in main
    requests, requests_df, warmup_requests = prepare_dataset(dataset_path=args.dataset_path,
  File "/mnt/ai-infra/users/wnd/workspace/execute/speculative-decoding-benchmark/3rdparty/llm-benchmark/src/llm_benchmark/benchmark/benchmark.py", line 155, in prepare_dataset
    prompt = row["prompt"]
  File "/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/lib/python3.10/site-packages/pandas/core/series.py", line 1133, in __getitem__
    return self._get_value(key)
  File "/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/lib/python3.10/site-packages/pandas/core/series.py", line 1249, in _get_value
    loc = self.index.get_loc(label)
  File "/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/lib/python3.10/site-packages/pandas/core/indexes/base.py", line 3819, in get_loc
    raise KeyError(key) from err
KeyError: 'prompt'
^MPreparing dataset:   0%|          | 0/18900 [00:00<?, ?it/s]


---

**Cursor**

错误很清晰：benchmark 工具在读 CSV 时要求有 `prompt` 列，我们的输出只有 `messages`。先看 benchmark 的数据读取逻辑：

看清楚了：benchmark 工具还需要 `prompt` 和 `request_id` 列。看一下 ziwei 的 CSV 确认标准列名：

问题找到了：第 109 行 `pd.read_csv(..., dtype={"prompt": str, ...})` 强制要求 `prompt` 列存在。`request_id` 是工具自动生成的（第 127 行），不需要我们提供。

标准列：`income_time, prompt(空), messages, old_response`

最快修法是直接给现有 CSV 加上空的 `prompt` 列，不用重跑整个脚本：

同步把处理脚本也修掉，下次不用补救：

---

**User**

修完了吗？ 没完成继续

---

**Cursor**

CSV 已修好，但还要把 `process_tianji_querysafety_full.py` 里的输出列也补上 `prompt`，不然下次重跑还是会缺。同时验证一下 benchmark 是否能正常读取：

脚本里已经是对的了（之前修 CSV 时顺手改了）。直接验证 benchmark 能否读取：

同时更新一下 SKILL，把这个坑记进去：

全部修完。总结：

**根因**：benchmark 工具在 `prepare_dataset` 里用 `dtype={"prompt": str, ...}` 强制读取，`prompt` 列缺失直接 KeyError。

**修复**：
1. ✅ 现有两个 CSV（`_peak30min.csv` / `_all.csv`）已插入空 `prompt` 列
2. ✅ `process_tianji_querysafety_full.py` 的 `OUTPUT_COLS` 已包含 `prompt`（后续生成不会再漏）
3. ✅ SKILL 常见错误表已补录这条

现在重新启动压测：

```bash
nohup bash scripts/benchmark/run_tianji_querysafety_qps_sweep.sh > /dev/null 2>&1 &
```

---

**User**

OK 我跑起来了，今天工作先这样
将本次会话内容做记录保存在 @progress.md  @project_status.md  ,参考 @.cursor/skills/progress-follower/SKILL.md  执行

---

**Cursor**

现在写本次会话的完整记录：

直接追加到文件末尾：

现在写 project_status.md：

记录完成。

---

**本次会话记录摘要**

`progress.md`（+165 行）记录了 7 个步骤的详细工作日志，`project_status.md`（155 行）写了完整的会话总结报告。

**今天完成的核心工作：**

| 成果 | 状态 |
|------|------|
| clingo/docs 文档体系 | ✅ |
| scripts/ 重组（15 个脚本分类）| ✅ |
| traffic-dataset-prep Skill（A+B 双路径，3 模型验证）| ✅ |
| model-onboarding.md SOP | ✅ |
| tianji 数据处理 + Demo 验证 | ✅ |
| tianji QPS 压测脚本 + 启动 | ✅ 🔄 运行中 |

**明天主要任务**：等 tianji 压测完成（~23h），跑 analysis 出报告；同时启动 hepan-72b 压测流程。

辛苦了，今天工作量很大。休息好！

