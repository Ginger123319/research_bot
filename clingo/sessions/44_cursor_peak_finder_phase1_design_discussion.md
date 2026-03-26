# 我刚刚跟同事讨论一下关于@clingo/docs/skills/qps-peak-finder ，第一个阶段从低位并发测...
_Exported on 2026/3/19 at GMT+8 19:10:05 from Cursor (transcript)_

---

**User**

我刚刚跟同事讨论一下关于@clingo/docs/skills/qps-peak-finder ，第一个阶段从低位并发测试的流程，假设我有对测试模型有一些先验知识，比如知道上线的并发数， 最大RPM或者是，TTFS 均值的述职情况下 ，那么从con 并发的起点数是不是就可以从一个合理的并发开始逐步得到phase1 阶段的结果，从而加快第一阶段的执行？ @.cursor/skills/brainstorming/SKILL.md 

---

**Cursor**

我先读取 brainstorming 技能和 qps-peak-finder 的相关文档，来更好地理解当前流程和你的想法。

The user is asking about optimizing the Phase 1 of the QPS peak finder process. They want to know if having prior knowledge about the model (like concurrent connections, max RPM, or TTFS mean values) can allow them to start from a more reasonable concurrency level instead of starting from the lowest point, thereby speeding up Phase 1.

They've mentioned the brainstorming skill, so I should read that first, then look at the qps-peak-finder skill to understand the current Phase 1 process.

Let me read the brainstorming skill first.

---

**Cursor**

现在读取 brainstorming skill：

Now let me read the brainstorming skill from the correct path.

---

**Cursor**

好，我已经理解了当前 Phase 1 的流程。这是一个很好的优化方向！让我们来 brainstorm 一下。

---

## 当前 Phase 1 的问题

现有流程从 `con=5` 开始，典型轨迹：

```
5 → 10 → 20 → 40 → 50 → 60 → 70（饱和）
```

每档 300s，7 档就是 **35 分钟**，而且前 4 档（5→40）几乎是"必然翻倍"的已知阶段，纯粹是在花时间确认显而易见的结论。

---

## 你的想法核心

有先验知识时，跳过"从 con=5 爬坡"的部分，直接从一个合理估算的并发数开始，进入"逼近饱和点"的精查阶段。

---

## 第一个澄清问题

在你说的先验知识里，有几种来源：
- **已知上线并发数**（如 Grafana 显示 active_requests ≈ 60）
- **已知最大 RPM**（需要结合平均响应时间才能推算并发）
- **已知 TTFS 均值**（只有首字延迟，不够推算总并发）

请问你的场景里，这三种先验知识通常是哪种最容易获得、最可靠？

> a) 直接看到 Grafana 上的 active_requests（即并发数）最直观  
> b) 上线 RPM 已知，但平均响应时间要估算  
> c) TTFS 均值已知，但 E2E 时长不确定

Now I have a good understanding of both the brainstorming skill and the qps-peak-finder skill. Let me analyze the user's question.

The user is asking: if they have prior knowledge about a model (like production concurrency, max RPM, or TTFS mean values), can they start Phase 1 from a more reasonable concurrency level instead of always starting from con=5, thereby speeding up Phase 1?

This is a brainstorming session. The user seems to be discussing a potential improvement to the qps-peak-finder skill. They're not asking me to implement anything yet - they're exploring whether this idea is sound.
 
Looking at how Phase 1 currently works, it starts at concurrency=5 and uses a two-phase stepping strategy that doubles when growth exceeds 10% or increments linearly for smaller growth rates, with each level running for 300 seconds. The key insight is that if you already know production metrics like the current concurrency level or max RPM, you could use those as a starting point to skip the early low-concurrency levels and reach the saturation point much faster. I'm exploring three concrete approaches for implementing this smart start feature: using prior knowledge to jump directly to an estimated concurrency level, starting at saturation and skipping the doubling phase entirely, or using prior knowledge to set bounds and binary search within them instead of the bottom-up approach. discussion, not a request for implementation yet. The brainstorming skill asks me to:
1. Explore project context ✓ (done)
2. Ask clarifying questions one at a time
3. Propose 2-3 approaches
4. Present design, get approval

Since this is a discussion about improving the skill (Phase 1 specifically), let me engage with the idea thoughtfully.

The core question is: **Can prior knowledge accelerate Phase 1?**

Yes, absolutely. The current Phase 1 starts from con=5 to be safe when there's zero prior knowledge. With prior knowledge, we can:
1. Skip the initial doubling phase (saves the most time)
2. Estimate where the saturation zone is and start just below it

Let me provide a thoughtful brainstorming response.

Looking at the current behavior: Phase 1 starts at con=5, doubles when growth exceeds 10%, and typically progresses through 7 steps over 35 minutes before hitting saturation around con=70. With prior knowledge like production metrics (600 RPM = 10 RPS, TTFS ≈ 5s), I could apply Little's Law to estimate saturation concurrency, though the challenge is we'd only have TTFS mean rather than full E2E timing. The real design question is determining what prior knowledge is reliably available and how conservative the starting estimate should be to avoid overshooting saturation.

---

**User**

 应该A选项，通过我或者操作人员看 Grafana 统计在执行钱告诉你这些信息来辅助你做起点并发数的设置，当然也可能这个模型还没上线就不会有这些信息。

---

**Cursor**

好，A 选项很清晰。下一个问题：

---

Grafana 上看到的 `active_requests`（如 60）反映的是**当前上线负载下的并发数**，不是饱和点的并发数——真正的饱和并发往往比这高很多。

所以"从合理起点开始"有两种理解方式：

> **a) 从生产并发数直接起跳**  
> 例如 Grafana 显示 active_requests ≈ 60，就从 con=60 开始，完全跳过低档位  
>  
> **b) 用生产并发数作为估算锚点，往上乘一个系数再起跳**  
> 例如 con=60 × 2 = 120 起跳，假设饱和点大概在生产负载的 2~3 倍区域  
>  
> **c) 用生产并发数定义"翻倍起点"，走简化版翻倍流程**  
> 例如从 con=60 开始翻倍（60→120→180），而不是从 5 开始，少走几步

你倾向于哪种？或者有其他想法？

The user clarifies that option A is the most common case - they can look at Grafana to get the active_requests (concurrency) and provide this info to the agent before starting Phase 1. But it's also possible the model hasn't been deployed yet, in which case there's no prior knowledge.

So the design needs to handle two cases:
1. Model already deployed: prior knowledge available (active_requests from Grafana)
2. New model, not yet deployed: no prior knowledge, fall back to current con=5 start

Let me ask the next clarifying question about how they want to use this information.

The key design question now: if we know production active_requests ≈ N, how do we use that to set Phase 1 starting concurrency?


Since saturation concurrency is typically 2-3x higher than production load, I need to clarify whether we should start Phase 1 at the production level itself or use some multiplier to be more aggressive.

---

**User**

A

---

**Cursor**

明白，从生产并发数直接起跳，干净利落。下一个问题：

---

当从 con=60（生产并发）直接起跳时，会有一个**"没有上一档对比基准"**的问题——当前饱和判断依赖"相邻两档吞吐增幅"，第一档没有前一档数据，无法计算增幅。

这种情况你倾向于哪种处理方式？

> **a) 从 con=production/2 跑一个"基准热身档"，再跳到 production 并发继续正常步进**  
> 例如生产 con=60，先跑 con=30 建立基准，再跳 con=60，后续按原规则走  
>  
> **b) 从 production 并发直接跑两档（con=N 和 con=N+10），通过比较这两档来判断是否在饱和区附近**  
> 跳过基准热身，但第一个有效判断要等第二档完成  
>  
> **c) 从 production 并发起跳后，只管继续往上翻倍/步进，不需要和低档位比较**  
> 核心假设：生产并发远低于饱和点，所以从这里开始翻倍一定能快速找到饱和区

The user chose option A: start directly from the production concurrency level (e.g., Grafana shows active_requests ≈ 60, so start from con=60).

Now I need to think about the implications of this approach and ask the next clarifying question. The key issue with option A is: what if the production concurrency is already at or near saturation? Or what if it's much lower than saturation? We need to understand how the stepping logic changes.

Actually, there's another important nuance: when we jump directly to con=60, we don't have the baseline readings from lower concurrency levels. The current saturation detection uses **relative increment between adjacent levels**. If we start at con=60 without any previous data points:


- We can't compare with a previous level
- We need a different way to determine if we're below/above/at saturation

The real question is how to bootstrap the saturation detection when starting at production concurrency. I could run a warm-up point at half the production level first to establish a baseline, or run two consecutive measurements at production concurrency to see if throughput stabilizes, or treat the first step as a special case and continue with the normal stepping logic from there.

Actually, the simplest approach is to just treat the production concurrency as your first data point and apply the same stepping rules—you run one more step and compare against it. The only difference is you've skipped the lower-level steps entirely.

But there's a practical concern: what if production concurrency is already above saturation? That's unusual but possible if the system is overloaded. Should there be a safety mechanism to detect if we've overshot, or should the agent have a way to know when to apply this optimization versus the default path—maybe based on whether the user provides prior info at startup?

---

**User**

C

---

**Cursor**

好，C 方案最简洁，而且逻辑上是对的——第一档直接跑 con=N，第二档跑 con=2N，之后按正常规则走，如果一上来就 <1% 增幅，说明生产并发已经在饱和区，照样能正确收敛。

最后一个问题：

---

这个先验信息（production active_requests）在什么时机传入给 Agent？

> **a) 在 SKILL.md 的"执行前"步骤里，明确要求 Agent 先问操作人员是否有 Grafana 数据，然后根据答复决定起始并发**  
> Agent 主动问，操作人员答，流程自适应  
>  
> **b) 作为一个可选环境变量/参数（如 `INIT_CONCURRENCY`），操作人员知道就传，不知道就走默认 con=5**  
> 类似现有的 `INIT_LO`/`INIT_HI` 环境变量设计风格，统一一致  
>  
> **c) 两者都要：SKILL.md 里提示 Agent 主动询问，同时脚本支持 `INIT_CONCURRENCY` 参数**  
> 既有人工交互引导，也有自动化路径

The user chose option C: start directly from production concurrency and continue doubling/stepping up without needing a baseline comparison. This makes sense because:
- Production concurrency is typically much lower than saturation point
- The current stepping rules still apply from that starting point
- You just skip the early low-concurrency levels

Now I need to ask the next clarifying question. Key remaining questions:
1. How should the agent prompt/detect if the user has this prior knowledge? At what point in the workflow does this get communicated?
2. What happens if the user provides production concurrency but the model hasn't been deployed yet (no prior knowledge available)?
3. What about the "overshoot" safety: if somehow the production concurrency IS near saturation, the C approach might jump right into the saturation zone and the first step would show <1% growth, immediately declaring saturation - which would actually work correctly!


4. For the bootstrap problem: without a baseline, the first step at production concurrency needs to establish whether we're in the doubling zone (growth > 10%), linear zone (1-10%), or already saturated (< 1%), and that single measurement determines the entire trajectory forward.

Now I'm thinking about how the agent actually learns this strategy—whether it comes from the user upfront, gets embedded in the benchmark script as a parameter, or if we should prompt the agent to ask clarifying questions before Phase 1 begins.

---

**User**

C

---

**Cursor**

很好，信息收集完毕。现在来呈现设计方案，请确认。

---

## 设计方案：Phase 1 先验并发加速

### 核心思路

在 Phase 1 开始前，通过两条路径传入 `INIT_CONCURRENCY`（Grafana active_requests），跳过低档位爬坡，直接从生产并发数起跳，后续沿用现有两段式步进规则。

---

### 变更点 1：SKILL.md — Phase 1 执行前增加询问步骤

在"Phase 1：饱和探测"的"执行"小节前，增加一个**人工信息收集检查点**：

```
### 执行前：先验信息收集（可选）

在启动 Phase 1 之前，询问操作人员：

> "模型是否已上线？若是，请提供 Grafana 上的 max active_requests 峰值（并发数）。
> 有此数据可跳过低档位爬坡，节省约 15~25 分钟。
> 若模型未上线或无数据，直接回复"无"，将从默认 con=5 开始。"

- 若提供了数值 N → 设置 INIT_CONCURRENCY=N，从 con=N 起跳
- 若回复"无" → INIT_CONCURRENCY 不设，从 con=5 走原始流程
```

---

### 变更点 2：脚本 — 支持 `INIT_CONCURRENCY` 环境变量

`run_phase1_saturation.sh` 脚本在初始化阶段增加：

```bash
# 若外部传入 INIT_CONCURRENCY，则从该并发起跳；否则默认 con=5
CONCURRENCY=${INIT_CONCURRENCY:-5}
```

用法示例（操作人员知道 Grafana 数据时）：

```bash
INIT_CONCURRENCY=60 bash run_phase1_saturation.sh
```

---

### 变更点 3：SKILL.md — 第一档逻辑说明

补充说明当有 `INIT_CONCURRENCY` 时，第一档没有前置基准的处理：

```
> **有 INIT_CONCURRENCY 时的第一步**：直接运行 con=INIT_CONCURRENCY，
> 将其作为翻倍起点（等效于认为更低并发已充分测试），
> 第二档运行 con=INIT_CONCURRENCY × 2，之后按正常饱和判断规则执行。
> 若第一档就已显示 <1% 增幅（对比第二档），说明生产并发已在饱和区，
> 直接退出并记录 peak。
```

---

### 时间节省估算

| 场景 | 步骤数 | 耗时 |
|------|--------|------|
| 默认 con=5 起跳（饱和在 con=60） | 7 档 | ~35 min |
| INIT_CONCURRENCY=60 起跳 | 3 档（60→120→饱和确认） | ~15 min |
| **节省** | 4 档 | **~20 min** |

---

这个设计方案看起来是否合理？有需要调整的地方吗？确认后我来更新 SKILL.md 和脚本。

The user chose option C: both SKILL.md prompts Agent to ask, AND the script supports `INIT_CONCURRENCY` parameter. Now I have enough information to propose the design. Let me present it.

Summary of decisions:
1. Prior knowledge source: Grafana active_requests (option A)
2. Starting strategy: Direct start from production concurrency, no warm-up baseline (option C)
3. First step logic: Treat first step as doubling mode, run con=N then con=2N, normal rules apply from there
4. Interface: Both SKILL.md asks + script `INIT_CONCURRENCY` parameter (option C)


5. Fallback: No prior knowledge → default con=5 (existing behavior)

Now I'm ready to present the full design for approval.

---

**User**

挺合理的，更新吧

---

**Cursor**

Now I need to implement the design. Let me:
1. Read the current SKILL.md for qps-peak-finder
2. Read the current run_phase1_saturation.sh script
3. Update both files

I already read the SKILL.md. Let me now read the script.

---

**Cursor**

现在来更新两个文件：

The script `run_phase1_saturation.sh` is a single-level runner - it runs ONE level at a time. The `CONCURRENCY` is passed as an environment variable each time it's called. So the INIT_CONCURRENCY concept is not really for this single-level script, but rather for the Agent's orchestration logic in SKILL.md.

Looking at the script, it requires `CONCURRENCY` to be set explicitly each time. So for the INIT_CONCURRENCY feature, the changes would be:

1. **SKILL.md**: Add a pre-Phase-1 checkpoint asking for Grafana active_requests, define `INIT_CONCURRENCY`, and modify the starting concurrency from `5` to `${INIT_CONCURRENCY:-5}`.


2. For the script itself, I could make `CONCURRENCY` optional with a default fallback to `${INIT_CONCURRENCY:-5}`, so it supports both being called directly with an explicit value and being invoked from SKILL.md where the initial concurrency is already determined. Actually, the design says the script should support `INIT_CONCURRENCY` env variable. But the script already takes `CONCURRENCY` directly. The simplest approach would be to:
1. In SKILL.md: change the starting `CONCURRENCY=5` to `CONCURRENCY=${INIT_CONCURRENCY:-5}` 
2. In the script: make `CONCURRENCY` fall back to `INIT_CONCURRENCY` if not explicitly set

Actually, re-reading the script: `CONCURRENCY="${CONCURRENCY:?必须设置 CONCURRENCY}"` - it requires CONCURRENCY to be set. We could change this to allow INIT_CONCURRENCY as fallback.

But wait - INIT_CONCURRENCY is the STARTING point, not every single level's concurrency. Each level, the Agent passes a specific CONCURRENCY. So INIT_CONCURRENCY only affects the first level. The orchestration happens in SKILL.md where the Agent reads the skill and follows instructions.

So the real changes needed are in SKILL.md: add a pre-Phase-1 step to ask the operator for Grafana active_requests and set INIT_CONCURRENCY, then update the initial concurrency variable to use that value with a fallback to 5, and document that this skips the ramp-up phase when we have prior concurrency data. The script itself is a single-level runner, so adding INIT_CONCURRENCY as a fallback there might be confusing since the Agent always sets CONCURRENCY explicitly anyway. I'll make the script accept INIT_CONCURRENCY as a fallback for CONCURRENCY, so the first invocation can use `INIT_CONCURRENCY=60 bash run_phase1_saturation.sh` while subsequent Agent calls pass CONCURRENCY directly. I need to update the script to check that at least one is set, and then revise SKILL.md to add a pre-Phase-1 inquiry step and clarify the starting concurrency logic.

---

**Cursor**

现在更新脚本：

---

**Cursor**

验证两个文件的改动：

---

**Cursor**

两个文件改动都正确。

---

**Cursor**

两处更新已完成，总结一下改动内容：

---

**`SKILL.md` 改动**（Phase 1 开头新增）：
- 执行前增加一个**人工检查点**，Agent 会主动询问操作人员是否有 Grafana active_requests 数据
- 有数据 → 设置 `INIT_CONCURRENCY=N`，起始并发从 N 起跳
- 无数据 → 回退默认 `con=5`，走完整流程
- 补充了第一档无基准时的处理逻辑（`con=N` → `con=N×2` 建立首个增幅对比）
- `CONCURRENCY=5` 改为 `CONCURRENCY=${INIT_CONCURRENCY:-5}`

**`run_phase1_saturation.sh` 改动**：
- `CONCURRENCY` 变为"可选"：优先使用显式传入值，回退到 `INIT_CONCURRENCY`，两者均未设置才报错
- 新增 `INIT_CONCURRENCY` 用法示例注释
- 向后完全兼容——原来的 `CONCURRENCY=20 bash run_phase1_saturation.sh` 用法不受影响

---

**User**

明白目前的 修改内容做一下 git commit 吧

---

**Cursor**

两个文件都是 untracked 的新文件，需要先 `git add` 再 commit：

The files I modified are untracked (new files), so `git diff` showed nothing. I need to `git add` them first and then commit. The two files are:
1. `.cursor/skills/qps-peak-finder/SKILL.md` (part of untracked `.cursor/skills/qps-peak-finder` directory)
2. `scripts/benchmark/run_phase1_saturation.sh` (untracked new file)

I should only commit these two specific files, not the other untracked/modified files.

---

**Cursor**

The `.cursor/skills/qps-peak-finder` might be a symbolic link or contain one. Let me check.

---

**Cursor**

`.cursor/skills/qps-peak-finder` 是指向 `clingo/docs/skills/qps-peak-finder` 的符号链接，应该提交真实路径：

`.cursor/skills/qps-peak-finder` is a symlink to `../../clingo/docs/skills/qps-peak-finder`. So the actual file is at `clingo/docs/skills/qps-peak-finder/SKILL.md`. Let me commit those files instead.

---

**Cursor**

Commit 成功，`00bc59a`。两个文件已一起提交：

- `clingo/docs/skills/qps-peak-finder/SKILL.md`（通过 symlink 对应 `.cursor/skills/qps-peak-finder/SKILL.md`）
- `scripts/benchmark/run_phase1_saturation.sh`

---

**User**

[attached files]
我看到今天的修改 还有很多没有提交
@/home/ceceadmin/.cursor/projects/mnt-ai-infra-users-wnd-workspace-execute-guofan/terminals/5.txt:585-639 
是否需要完成相关内容的commit 也做对应的提交任务？

---

**Cursor**

这些改动跨越了多个会话和功能模块，内容比较杂。我先快速看一下各文件的改动范围，再给你建议分组方案：

The user is asking whether they should commit all the other modified/untracked files shown in git status. Let me look at what's there:

Modified files:
- clingo/delay/2026-03-dalily_report.md
- clingo/docs/skills/llm-replay-benchmark/SKILL.md
- clingo/docs/skills/model-evaluation-workflow/SKILL.md
- clingo/docs/skills/qps-benchmark-sweep/SKILL.md
- clingo/docs/skills/traffic-dataset-prep/SKILL.md
- progress.md
- project_status.md


- results/README.md
- scripts/benchmark/run_chart_4tp_qps_sweep.sh
- scripts/benchmark/run_chart_8tp_qps_sweep.sh
- scripts/data/process_guoxue_full.py
- scripts/serve.py

There are also some deleted files (the old chart processing scripts) and a couple of untracked items like a symlink and a superpowers directory that probably shouldn't be committed.

Now I'm looking at a bunch of new files and directories that have been added or modified: design documents for the benchmark runner, QPS peak finder, and dashboard saturation metrics, along with various analysis scripts, configuration files for chart comparisons, and benchmark execution scripts for different phases and grids.

I'm realizing there are quite a few changes across multiple sessions here, and I should probably check with the user about whether they want to commit everything at once or be more selective about what goes in.

---

**Cursor**

内容很多，跨越好几个会话。建议按功能分组提交，这样历史更清晰：

---

**建议分组（共 5 个 commit）：**

| # | Commit 内容 | 文件 |
|---|------------|------|
| 1 | **压测脚本**：Phase 1/2 自动化 + qps sweep + replay 脚本（新增） | `run_phase1_auto_*.sh`, `run_phase2_auto*.sh`, `run_phase2_probe.sh`, `run_qps_sweep.sh`, `run_replay.sh`, `run_chart_*_qps_sweep.sh` |
| 2 | **分析脚本**：peak finder 分析 + badcase/null decode 提取 | `scripts/analysis/analyze_peak_finder.py`, `build_badcase_csv.py`, `extract_null_decode.py` |
| 3 | **数据处理脚本**：新版 process.py + v3 + guoxue 更新，删除旧版 | `scripts/data/process.py`, `process_chart_full_v3.py`, `process_guoxue_full.py`，删除 `process_chart_full*.py` |
| 4 | **Skill 文档 + 设计文档**：llm-replay/model-eval-workflow/qps-benchmark-sweep/traffic-dataset-prep 更新，新增 3 个设计文档 | `clingo/docs/skills/*.md`, `clingo/docs/designs/*.md`, `results/README.md`, `clingo/docs/ai_data/` |
| 5 | **进度文档**：progress.md / project_status.md / daily report | `progress.md`, `project_status.md`, `clingo/delay/2026-03-dalily_report.md` |

> 其他（`configs/`, `scripts/serve.py`, `clingo/sessions/`, `.superpowers/`）可附在对应分组里，或单独提交。

---

要我按这个分组依次执行提交吗？还是你有其他想法？

Now I have a clearer picture. Let me suggest grouping these into logical commit groups:

1. **进度文档** (progress.md, project_status.md, clingo/delay/2026-03-dalily_report.md)
2. **Skill 文档更新** (clingo/docs/skills/llm-replay-benchmark/SKILL.md, model-evaluation-workflow/SKILL.md, qps-benchmark-sweep/SKILL.md, traffic-dataset-prep/SKILL.md)
3. **压测脚本** - Phase 1/2 自动化脚本 + qps sweep 脚本 + replay脚本


4. **分析和数据处理脚本** (scripts/analysis/*.py, scripts/data/process.py, process_chart_full_v3.py, process_guoxue_full.py)
5. **设计文档** (clingo/docs/designs/*.md)
6. **其他杂项** (results/README.md, scripts/serve.py, configs/, clingo/docs/ai_data/, clingo/sessions/)

Before I finalize this, I should check with the user whether they want all these changes committed separately or if they'd prefer a different grouping strategy.

---

**User**

可以的

---

**Cursor**

Let me now execute the 5 commits in order. I'll be careful to only add the specific files for each commit.

---

**Cursor**

**Commit 1：压测脚本**

---

**Cursor**

**Commit 2：分析脚本**

---

**Cursor**

**Commit 3：数据处理脚本**

---

**Cursor**

**Commit 4：Skill 文档 + 设计文档 + results/README + ai_data**

---

**Cursor**

`results/` 被 `.gitignore` 忽略，跳过它继续提交其余文件：

`results/` is in `.gitignore`. I'll skip it and commit the rest.

---

**Cursor**

**Commit 5：进度文档**

---

**Cursor**

5 个 commit 全部完成，本地领先 origin/main 共 6 个提交：

| Commit | 内容 |
|--------|------|
| `00bc59a` | feat: INIT_CONCURRENCY 加速 Phase 1 |
| `86af757` | feat: Phase 1/2 自动化压测脚本 |
| `e6ae486` | feat: peak finder 分析脚本 |
| `bdccaee` | refactor: 数据处理脚本整合，删除旧版 |
| `3647ccc` | docs: Skill/设计文档/ai_data 更新 |
| `9a834f3` | docs: 进度日志与项目状态 |

> 注：`results/` 目录在 `.gitignore` 中，已跳过。需要提交时须用 `git add -f`，是否需要单独处理？

---
