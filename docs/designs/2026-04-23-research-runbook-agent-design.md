# 设计文档：Research Runbook Agent（原始材料优先 + 相关度分层 + 可执行手册）

> 写于 2026-04-23 | 状态：已通过评审，待实现

---

## 背景

本项目的核心交付物是“**面向 Agent 阅读的调研文档**”。当前 `docs/results/` 已形成“结论前置 + 分维度分析 + 局限性 + 参考来源”的报告范式，但在“**真实性（可追溯）**、**小切口（问题足够具体）**、**可落地（Runbook 形态）**”三个方向需要进一步固化为可复用的机器人工作流。

本设计将调研机器人（Research Bot）的默认交付物定位为：

- **Runbook / 排障手册 / 部署 Playbook**：以“步骤 + 验证点 + 分支决策 + 回滚/兜底”为主，而非泛综述。

同时，新增一个强约束模块：

- **Source Relevance & Authority（来源权威性×相关度×可访问性）**：越官方、越原始（代码/论文/官方文档）、越贴近问题的材料优先作为主依据；并要求显式输出可访问性状态（ok/blocked/not_found）。

---

## 目标（Goals）

1. **原始材料优先**：官方文档、官方代码、论文的优先级最高，并成为 Runbook 主线的主要依据。
2. **召回更全**：先尽可能抓全候选材料，再分层筛选，避免因术语不一致/命名变体导致漏掉关键材料。
3. **相关度可解释**：对每条候选材料给出相关度评分与一句理由，并输出“Source Relevance & Authority 表”。
4. **可访问性透明**：对最相关但不可访问的材料，明确提示用户“可能最相关/最官方，但当前无法访问”，并给可用替代材料。
5. **可落地**：输出 Runbook 时，每一步必须带验证点与下一步分支条件；关键结论必须可追溯到来源。

---

## 非目标（Non-goals）

- 不追求一次性覆盖所有相邻问题（坚持“小切口”，同类问题拆分为多份 Runbook）。
- 不把 S2（一般博客/营销）作为关键结论的唯一证据来源。
- 不要求机器人在用户环境中实际执行命令（如需，另立“可执行验证模式”扩展）。

---

## 一、整体架构（七阶段 + 双通道召回）

调研 SOP 仍遵循七阶段顺序（需求澄清 → 拆解 → 搜集 → 去噪 → 分析 → 输出 → 使用指导），其中 **阶段三～四**按“召回更全”策略增强为：

```
阶段三：信息搜集（双通道召回）
  A. 官方/原始优先召回（S0-only query set）
  B. 广谱召回（S0/S1/S2，术语扩展）
        ↓
阶段四：筛选与去噪（先收全→硬筛入主线）
  - 低门槛入库：Relevance ≥ 2 即进入候选池
  - 硬筛入主线：S0/S1 + Relevance ≥ 4 + Access=ok
  - blocked 特判：S0 且 Relevance=5 但 blocked → 列为 Top Candidate（blocked）并给可执行替代
```

### 阶段产物与接口（Implementation-facing）

为保证可实现性与可测试性，每个阶段必须以“结构化产物”承接下游，不允许仅靠自然语言上下文传递关键判断。

**核心数据结构：`SourceCandidate`**

```json
{
  "id": "stable_id",
  "title": "string",
  "type": "doc|code|paper",
  "authority": "S0|S1|S2",
  "relevance": 0,
  "relevance_rationale": "one_sentence",
  "access": "ok|blocked|not_found",
  "url": "string",
  "canonical_url": "string|null",
  "version": "string|null",
  "published_date": "YYYY-MM-DD|null",
  "retrieved_at": "ISO-8601|null",
  "evidence_kind": "fulltext|snippet|metadata_only|inferred",
  "evidence_locator": {
    "doc_section": "string|null",
    "code_path": "string|null",
    "code_ref": "branch|tag|commit|null",
    "issue_pr": "string|null",
    "paper_section": "string|null"
  },
  "extracted_snippet": "string|null",
  "extracted_snippet_locator": "line_range|quote_span|null",
  "notes": "string|null",
  "alternatives": [
    { "title": "string", "url": "string", "reason": "string" }
  ]
}
```

**阶段输入/输出（最小闭环）**

- **阶段一（需求澄清）输出**：`ProblemBrief`
  - `problem_statement`（一行小切口问题）
  - `environment`（平台/版本/约束）
  - `success_criteria`（可测指标）
- **阶段二（拆解）输出**：`SubQuestions[]`
  - 每项包含：`name`、`why`、`keywords[]`、`acceptance_signal`（什么证据算回答到）
- **阶段三（搜集）输出**：`SourceCandidate[]`（允许低质量/重复，强调召回）
- **阶段四（去噪）输出**：`RankedSources`（去重、归并 canonical、标注 access、确定候选 Top）
- **阶段五（分析）输出**：`Claims[]`
  - `claim`、`confidence`、`applicability`、`evidence[] (SourceCandidate.id)`
- **阶段六（输出）产物**：Runbook Markdown + `Source Relevance & Authority` 表 + Claim Table
- **阶段七（使用指导）产物**：固定的“阅读路径引导（<=400字）”

---

## 二、来源分层（Authority）

### Authority 等级

- **S0（最高）**：官方/原始材料
  - 官方文档（官网、官方 GitHub Wiki、官方 release note/公告）
  - 官方代码仓库（含具体文件、commit、PR、Issue/Discussion）
  - 论文（arXiv/会议）及其官方实现/附录
- **S1**：权威二手材料
  - 同行评审报告
  - 核心维护者/核心贡献者的公开演讲/帖子（可溯源身份）
- **S2**：一般二手材料
  - 博客、教程、媒体文章、厂商营销页

### 证据使用规则（硬规则）

- **Runbook“主步骤/关键结论”只允许引用 S0/S1**。
- **S2 只能进入“背景解释/经验提示/常见坑”**，且必须显式标注为二手材料。

---

## 三、相关度模型（Relevance）与可访问性（Access）

### Relevance 评分（0～5）

只衡量“材料是否能直接解决当前问题”，与写作质量无关：

- **5**：直接覆盖目标（专章/官方示例/参数与拓扑说明/明确的操作步骤）
- **4**：同一子系统强相关（机制说明 + 可映射到当前问题的关键约束/接口）
- **3**：同产品间接相关（概览、调优、架构，提到但缺操作细节）
- **1-2**：仅背景或类比
- **0**：无关

### Access 状态

- **ok**：可访问且已读取内容
- **blocked**：判断为高相关/高权威，但当前无法访问（网络/权限/失效）
- **not_found**：未找到（给出检索边界与可能原因）

---

## 四、Source Relevance & Authority 表（必出）

每份调研输出必须包含该表，并按以下综合排序：

**排序优先级**：Authority（S0>S1>S2） > Relevance（5→0） > Access（ok>blocked>not_found）

表字段固定：

- Title
- Type（doc | code | paper）
- Authority（S0/S1/S2）
- Relevance（0-5）+ 一句理由（必须点出“如何直接对上当前问题”）
- Version & Date（能判定则必填）
- Access（ok/blocked/not_found）
- URL（必填；代码必须尽量精确到文件/目录/commit/PR/Issue 链接）
- Alternatives（当 Access != ok 时必填：1-2 个可访问替代材料）

---

## 五、blocked 最相关材料（强制声明）

若出现 “**S0 且 Relevance=5 但 Access=blocked**” 的材料：

1. **必须列为 Top Candidate（blocked）**，并明确提示：
   - “可能最相关/最官方，但当前无法访问到”
2. 必须补充三段内容：
   - **为何判断最相关**：基于标题/目录/引用链/版本说明等（不得伪装成已读内容）
   - **当前可执行替代**：用可访问的 S0/S1 组成临时 Runbook 主线
   - **获取建议**：提供可能的获取路径（镜像、raw、tag、替代入口等）

### Anti-hallucination 护栏（硬规则）

为防止“未访问却引用/摘录”的核心失败模式：

- **Access != ok 时禁止摘录**：不得输出任何看似来自正文的引用/代码片段/逐字复述；只能输出“基于元信息的推断”（`evidence_kind=metadata_only|inferred`）。
- **Access=ok 才允许引用**：若要支持某条 claim，必须满足：
  - 绑定到 `SourceCandidate.id`，并在表格/Claim Table 中可追溯到 URL
  - 若来源是代码：必须给出 `code_path` + `code_ref`（tag/commit 优先）或 PR/Issue 链接
- **blocked 的 Relevance=5 允许但必须降权**：只能作为“关键结论候选/待确认”，不得作为 Runbook 主线的唯一依据。

---

## 六、Runbook 输出格式（docs/results，固定模板）

输出路径：

- `docs/results/YYYY-MM-DD-<topic>-runbook.md`
- `docs/sessions/NN_<topic>_research.md`（保留 query、筛选理由、去噪过程）

> 注：本仓库已有 `docs/results/` 与 `docs/sessions/` 作为调研产出目录，本设计沿用该约定，不新增平行目录。

### Runbook 固定结构（Markdown）

```markdown
# Runbook：<问题名（小切口）>

> 调研日期：
> 适用范围（版本/环境/前置条件）：
> 成功判据（可测指标）：

## 阅读路径引导（<= 400 字）

## 一句话摘要（最短可执行路径）

## 0. Source Relevance & Authority（必出）
（表格）

## 1. 快速检查（~10 分钟）
- 每条包含：动作 / 期望观测 / 若不满足跳转到哪一节

## 2. 分支排查树（从观测到结论）
（按观测条件分支，指向具体小节）

## 3. 修复步骤（按无损→可回滚→破坏性）
### 3.1 Step：<动作名>
- 目的：
- 动作：
- 验证点（必须可观测）：
- 风险：
- 回滚/兜底：
- 下一步分支：

## 4. 已验证关键主张（Claim Table）
（claim / 证据A / 证据B / 置信度 / 适用版本 / 备注）

## 5. 局限性与待验证项

## 6. 参考来源（URL 清单）
```

---

## 七、关键门槛（硬筛规则汇总）

### 候选池入库（高召回）

- 满足 **Relevance ≥ 2** 即入库（S0/S1/S2 均可）

### Runbook 主线（硬筛）

- 进入“主步骤/关键结论/修复建议”的证据必须满足：
  - **Authority ∈ {S0, S1}**
  - **Relevance ≥ 4**
  - **Access = ok**

### blocked 特判（避免漏掉最关键官方材料）

- 若 **S0 & Relevance=5 & Access=blocked**：
  - 允许进入“关键结论候选”，但必须显式标注 blocked
  - 必须提供可访问替代材料支撑当下可执行路径

### 置信度（Confidence）定义与冲突处理

**置信度等级（用于 Claim Table）**

- **高**：同一 claim 有 ≥2 个独立 S0/S1 证据，且版本适用范围一致或可解释差异
- **中**：仅 1 个 S0/S1 证据，但可通过明确的实验/验证点在本地快速确认（Runbook 已给验证步骤）
- **低**：仅 S2 或存在明显冲突且无法在 Runbook 内给出可操作验证

**冲突处理（例如两个 S0 结论不一致）**

- 必须显式记录“冲突点”与“可能原因”（版本差异/默认值变化/平台差异）
- Runbook 主线默认走“**最安全可回滚路径**”，并把另一结论放入分支与验证点中
- 若冲突无法在当前信息范围内消解：将该 claim 标注为 **低**，并进入“待验证项”

### Relevance 阈值的降级策略（保证可交付）

原则：不为了满足阈值而输出空 Runbook。

- 若在 S0/S1 中找不到 `Relevance ≥ 4` 的可访问材料，但存在 `Relevance=3` 的强相关材料：
  - 允许 Runbook 主线使用 `Relevance=3` 的 S0/S1，但必须：
    - 把对应 claim 的置信度最多标为 **中**
    - 强制加入可观测验证点，避免“凭概览下结论”

---

## 八、示例：SGLang 的 PD 分离部署（检索与分层示意）

当输入问题为 “SGLang 的 PD 分离部署” 时：

- **优先召回（S0-only）**：
  - SGLang 官方文档中直接命中的部署章节/参数说明/拓扑示例
  - 官方代码仓库中与 PD/Prefill/Decode/Disagg 相关的入口、示例、配置解析、组件拆分
  - 相关 release note/PR/Issue（若官方文档不足，代码与 PR 往往是最原始依据）
- **广谱召回**：
  - 同义词/别名检索（PD、prefill/decode separation、disaggregated serving、prefill node、decode node、kv cache 等）
  - 用于发现术语差异、历史命名或未被官方文档集中整理的材料

输出时必须包含：

- Source Relevance & Authority 表（含 URL 与 Access 状态）
- 若发现“最相关但 blocked”的官方材料：按 blocked 强制声明格式输出
- Runbook 主线只引用可访问的 S0/S1（blocked 材料作为候选，不伪装成已验证）

### 示例片段（最小端到端，格式校验用）

> 说明：下例只展示“表格 + 2 条快速检查 + 1 条修复步骤”的最小闭环，便于实现时对齐格式与约束。

**0. Source Relevance & Authority（片段）**

| Title | Type | Authority | Relevance | Access | URL | Alternatives |
|---|---|---:|---:|---|---|---|
| SGLang 官方：Disaggregated / PD deployment 文档（假设标题） | doc | S0 | 5（直接覆盖 PD 分离部署） | blocked | `<official-doc-url>` | `<repo-readme-or-release-url>`（可访问的官方替代入口） |
| SGLang GitHub：PD/Disagg 示例目录（假设） | code | S0 | 4（提供启动与拓扑示例） | ok | `<github-repo-examples-url>` | — |

**1. 快速检查（片段）**

- 动作：确认当前部署拓扑是否真的“prefill 与 decode 分离”（检查服务端启动参数/组件进程）
  - 期望观测：存在独立的 prefill / decode worker（或对应角色标识）
  - 若不满足：跳转到 “2. 分支排查树 → 未启用 PD 分离”

- 动作：确认请求路由是否把 prefill 请求打到正确角色（查看路由规则/日志关键字）
  - 期望观测：prefill 与 decode 命中不同后端
  - 若不满足：跳转到 “3. 修复步骤 → 修复路由/服务发现”

**3. 修复步骤（片段）**

### Step：修复路由/服务发现（PD 分离场景）
- 目的：确保 prefill 与 decode 请求分发到对应后端，避免“名义分离、实际混跑”
- 动作：按官方/代码示例中的推荐配置更新路由（给出配置项/参数名），并重启相关组件
- 验证点：同一请求在日志中出现“prefill 命中 A、decode 命中 B”的可观测证据
- 风险：路由变更导致短暂 5xx；需要流量切换或灰度
- 回滚/兜底：恢复原路由配置并重启；或临时关闭 PD 分离回到单体模式
- 下一步分支：若路由正确但吞吐仍异常 → 进入“排查瓶颈：KV cache / 网络带宽 / batch 策略”

---

## 九、验证标准（Definition of Done）

实现完成后，至少用 1 个真实主题生成 Runbook，满足：

- 产出包含“Source Relevance & Authority 表”，且 URL 可追溯
- 主线结论可追溯到 S0/S1 且可访问材料
- 出现 blocked 场景时，能明确提示并给替代方案
- Runbook 每一步都有验证点与分支跳转

### DoD 扩展（更可测）

至少覆盖以下 3 类测试主题（可先用同一领域不同输入）：

1. **blocked Top S0**：最相关官方文档不可访问，但存在可访问的官方代码/PR 作为替代
2. **冲突证据**：两个 S0 来源对默认参数/行为描述不一致（版本差异），Runbook 能输出分支与验证点
3. **code-heavy**：官方文档缺失，主要依据来自代码/PR/Issue，仍能输出可执行步骤与验证点

每个主题的 pass/fail：

- 必须包含 `Source Relevance & Authority` 表，且至少 **2 条 S0**（doc+code 组合优先）
- Claim Table 中任意 **高/中** 置信度 claim 必须绑定 ≥1 个 S0/S1 证据（Access=ok）
- blocked 场景下不得出现“引用式摘录”（满足 Anti-hallucination 规则）

